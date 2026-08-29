-- Reliably dispatch correction pushes from the committed database write.
-- Existing push_subscriptions, push_delivery_log and Edge Function remain the source of truth.

create extension if not exists pg_net with schema extensions;

-- The existing Edge Function uses the service role, but this table was created
-- without write grants. Keep RLS enabled and grant only the operations needed
-- for delivery deduplication and rollback after a failed provider request.
grant select, insert, delete on table public.push_delivery_log to service_role;
grant select, delete on table public.push_subscriptions to service_role;

do $$
begin
  if not exists(select 1 from vault.secrets where name='push_dispatch_webhook_key') then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32),'hex'),
      'push_dispatch_webhook_key',
      'Authenticates database-to-Edge push dispatch',
      null
    );
  end if;
end;
$$;

create or replace function public.push_dispatch_webhook_key()
returns text
language sql
stable
security definer
set search_path=public,vault
as $$
  select decrypted_secret from vault.decrypted_secrets where name='push_dispatch_webhook_key' limit 1
$$;
revoke all on function public.push_dispatch_webhook_key() from public,anon,authenticated;
grant execute on function public.push_dispatch_webhook_key() to service_role;

create or replace function public.dispatch_correction_push_from_database()
returns trigger
language plpgsql
security definer
set search_path=public,vault,extensions
as $$
declare
  guardian_profile_id uuid;
  dispatch_key text;
  student_name text;
begin
  if new.published is not true then return new; end if;
  if tg_op='UPDATE'
     and (to_jsonb(new)-array['updated_at','created_at'])
         is not distinct from (to_jsonb(old)-array['updated_at','created_at']) then
    return new;
  end if;
  select decrypted_secret into dispatch_key from vault.decrypted_secrets where name='push_dispatch_webhook_key' limit 1;
  select name into student_name from public.students where id=new.student_id;
  for guardian_profile_id in
    select distinct g.profile_id
    from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id
    where sg.student_id=new.student_id and g.profile_id is not null
  loop
    perform net.http_post(
      url:='https://dngxryzhlbeiqpbdzndm.supabase.co/functions/v1/send-learning-feed-push',
      headers:=jsonb_build_object('Content-Type','application/json','x-push-dispatch-key',dispatch_key),
      body:=jsonb_build_object(
        'kind','correction','sourceKey',new.id::text||':'||new.updated_at::text,'studentIds',jsonb_build_array(new.student_id),
        'recipientProfileId',guardian_profile_id,'date',new.correction_date::text,
        'title','새 첨삭 기록이 도착했어요',
        'body',coalesce(student_name,'자녀')||' 학생의 '||to_char(new.correction_date,'MM.DD')||' '||coalesce(new.subject,'')||' 첨삭 기록이 등록되었습니다.',
        'url','/'
      )
    );
  end loop;
  return new;
end;
$$;

drop trigger if exists correction_report_dispatch_push on public.correction_reports;
create trigger correction_report_dispatch_push
after insert or update on public.correction_reports
for each row execute function public.dispatch_correction_push_from_database();

revoke all on function public.dispatch_correction_push_from_database() from public,anon,authenticated;

notify pgrst,'reload schema';
