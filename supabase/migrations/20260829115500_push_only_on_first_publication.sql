-- Send correction push only when a report becomes visible to the family for
-- the first time. Later edits to an already-published report must stay silent.

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
  if tg_op='UPDATE' and old.published is true then return new; end if;

  select decrypted_secret into dispatch_key
  from vault.decrypted_secrets
  where name='push_dispatch_webhook_key'
  limit 1;

  select name into student_name
  from public.students
  where id=new.student_id;

  for guardian_profile_id in
    select distinct g.profile_id
    from public.student_guardians sg
    join public.guardians g on g.id=sg.guardian_id
    where sg.student_id=new.student_id and g.profile_id is not null
  loop
    perform net.http_post(
      url:='https://dngxryzhlbeiqpbdzndm.supabase.co/functions/v1/send-learning-feed-push',
      headers:=jsonb_build_object(
        'Content-Type','application/json',
        'x-push-dispatch-key',dispatch_key
      ),
      body:=jsonb_build_object(
        'kind','correction',
        'sourceKey',new.id::text,
        'studentIds',jsonb_build_array(new.student_id),
        'recipientProfileId',guardian_profile_id,
        'date',new.correction_date::text,
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
after insert or update of published on public.correction_reports
for each row execute function public.dispatch_correction_push_from_database();

revoke all on function public.dispatch_correction_push_from_database()
from public,anon,authenticated;
