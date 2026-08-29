-- Reuse the existing push tables and Edge Function for assigned-teacher
-- comment alerts. A browser push endpoint belongs to the currently signed-in
-- eligible account only, preventing cross-account alerts on shared devices.

drop policy if exists "guardians manage own push subscriptions" on public.push_subscriptions;
drop policy if exists "eligible profiles manage own push subscriptions" on public.push_subscriptions;
create policy "eligible profiles manage own push subscriptions"
on public.push_subscriptions
for all to authenticated
using (
  profile_id=(select auth.uid())
  and exists(
    select 1 from public.profiles p
    where p.id=(select auth.uid())
      and p.role::text in ('guardian','teacher','admin','manager')
  )
)
with check (
  profile_id=(select auth.uid())
  and exists(
    select 1 from public.profiles p
    where p.id=(select auth.uid())
      and p.role::text in ('guardian','teacher','admin','manager')
  )
);

create or replace function public.set_current_device_push_subscription(
  p_endpoint text,
  p_p256dh text default null,
  p_auth text default null,
  p_user_agent text default null,
  p_enabled boolean default true
)
returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare
  current_role text;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다.'; end if;
  if nullif(trim(coalesce(p_endpoint,'')),'') is null then raise exception '기기 구독 주소가 필요합니다.'; end if;

  select role::text into current_role from public.profiles where id=auth.uid() and is_active is true;

  -- The endpoint is an unguessable browser capability. Removing every stale
  -- owner is what makes account switching on one PWA safe.
  delete from public.push_subscriptions where endpoint=p_endpoint;

  if not p_enabled then return false; end if;
  if current_role not in ('guardian','teacher','admin','manager') then
    raise exception '이 계정은 기기 알림을 사용할 수 없습니다.';
  end if;
  if nullif(trim(coalesce(p_p256dh,'')),'') is null or nullif(trim(coalesce(p_auth,'')),'') is null then
    raise exception '기기 구독 키가 필요합니다.';
  end if;

  insert into public.push_subscriptions(profile_id,endpoint,p256dh,auth,user_agent,updated_at)
  values(auth.uid(),p_endpoint,p_p256dh,p_auth,p_user_agent,now())
  on conflict(profile_id,endpoint) do update
  set p256dh=excluded.p256dh,auth=excluded.auth,user_agent=excluded.user_agent,updated_at=now();
  return true;
end;
$$;

revoke all on function public.set_current_device_push_subscription(text,text,text,text,boolean) from public,anon;
grant execute on function public.set_current_device_push_subscription(text,text,text,text,boolean) to authenticated;

create or replace function public.dispatch_new_family_comment_push()
returns trigger
language plpgsql
security definer
set search_path=public,vault,extensions
as $$
declare
  recipient_profile_id uuid;
  dispatch_key text;
  student_name text;
  guardian_name text;
begin
  if new.parent_id is not null then return new; end if;

  if new.lesson_id is not null then
    select l.teacher_profile_id into recipient_profile_id
    from public.lessons l where l.id=new.lesson_id;
  elsif new.special_lesson_id is not null then
    select sl.teacher_profile_id into recipient_profile_id
    from public.teacher_special_lessons sl where sl.id=new.special_lesson_id;
  end if;

  if recipient_profile_id is null or recipient_profile_id=new.author_profile_id then return new; end if;
  if not exists(select 1 from public.push_subscriptions ps where ps.profile_id=recipient_profile_id) then return new; end if;

  select decrypted_secret into dispatch_key
  from vault.decrypted_secrets where name='push_dispatch_webhook_key' limit 1;
  select name into student_name from public.students where id=new.student_id;
  select display_name into guardian_name from public.profiles where id=new.author_profile_id;

  perform net.http_post(
    url:='https://dngxryzhlbeiqpbdzndm.supabase.co/functions/v1/send-learning-feed-push',
    headers:=jsonb_build_object('Content-Type','application/json','x-push-dispatch-key',dispatch_key),
    body:=jsonb_build_object(
      'kind','comment',
      'sourceKey',new.id::text,
      'studentIds',jsonb_build_array(new.student_id),
      'recipientProfileId',recipient_profile_id,
      'date',to_char(new.created_at at time zone 'Asia/Seoul','YYYY-MM-DD'),
      'title',coalesce(student_name,'학생')||' 학생에게 새 댓글이 도착했어요',
      'body',coalesce(guardian_name,'학부모')||' 학부모님이 학습 피드에 댓글을 남겼습니다.',
      'url','/'
    )
  );
  return new;
end;
$$;

drop trigger if exists new_family_comment_push on public.learning_report_comments;
create trigger new_family_comment_push
after insert on public.learning_report_comments
for each row
when (new.parent_id is null)
execute function public.dispatch_new_family_comment_push();

revoke all on function public.dispatch_new_family_comment_push() from public,anon,authenticated;
