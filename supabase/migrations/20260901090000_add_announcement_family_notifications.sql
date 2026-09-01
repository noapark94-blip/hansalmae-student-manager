-- 공개된 학원 공지를 학생·학부모 알림센터에 대상별로 전달합니다.

alter table public.family_notifications drop constraint if exists family_notifications_source_type_check;
alter table public.family_notifications add constraint family_notifications_source_type_check
  check (source_type in ('attendance','makeup','tuition','learning_report','announcement'));

create or replace function public.sync_family_announcement_notifications()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.current_user_role() not in ('student','guardian') then return; end if;

  insert into public.family_notifications(student_id,recipient_profile_id,event_key,title,body,source_type,source_id,created_at)
  select min(s.id),auth.uid(),'announcement','학원 공지 · '||a.title,a.body,'announcement',a.id,coalesce(a.published_at,a.created_at)
  from public.announcements a
  join public.students s on s.status in ('active','재원') and (
    a.audience='all'
    or (a.audience='student' and s.id=a.student_id)
    or (a.audience='class' and exists(
      select 1 from public.enrollments e where e.student_id=s.id and e.class_id=a.class_id and e.status='active'
    ))
  )
  where a.published_at is not null and a.published_at<=now() and (a.expires_at is null or a.expires_at>now())
    and (s.profile_id=auth.uid() or exists(
      select 1 from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id
      where sg.student_id=s.id and g.profile_id=auth.uid()
    ))
  group by a.id,a.title,a.body,a.published_at,a.created_at
  on conflict(recipient_profile_id,event_key,source_type,source_id)
  do update set title=excluded.title,body=excluded.body;
end;
$$;

create or replace function public.family_notification_center()
returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
  perform public.sync_family_announcement_notifications();
  select jsonb_build_object(
    'unreadCount',count(*) filter(where n.read_at is null),
    'items',coalesce(jsonb_agg(jsonb_build_object(
      'id',n.id,'studentName',s.name,'eventKey',n.event_key,'title',n.title,'body',n.body,
      'sourceType',n.source_type,'sourceId',n.source_id,'readAt',n.read_at,'createdAt',n.created_at
    ) order by n.created_at desc),'[]'::jsonb)
  ) into result
  from (select * from public.family_notifications where recipient_profile_id=auth.uid() order by created_at desc limit 50) n
  join public.students s on s.id=n.student_id;
  return result;
end;
$$;

revoke all on function public.sync_family_announcement_notifications() from public;
revoke all on function public.family_notification_center() from public;
grant execute on function public.family_notification_center() to authenticated;
notify pgrst,'reload schema';
