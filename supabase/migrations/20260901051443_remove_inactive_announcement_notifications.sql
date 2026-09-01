-- 종료·삭제되었거나 더 이상 대상이 아닌 공지는 가족 알림함에서도 정리합니다.

create or replace function public.sync_family_announcement_notifications()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null or public.current_user_role() not in ('student','guardian') then return; end if;

  delete from public.family_notifications n
  where n.recipient_profile_id=auth.uid() and n.source_type='announcement'
    and not exists (
      select 1 from public.announcements a
      join public.students s on s.status in ('active','재원') and (
        a.audience='all'
        or (a.audience='student' and s.id=a.student_id)
        or (a.audience='class' and exists(
          select 1 from public.enrollments e where e.student_id=s.id and e.class_id=a.class_id and e.status='active'
        ))
      )
      where a.id=n.source_id
        and a.published_at is not null and a.published_at<=now()
        and (a.expires_at is null or a.expires_at>now())
        and (s.profile_id=auth.uid() or exists(
          select 1 from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id
          where sg.student_id=s.id and g.profile_id=auth.uid()
        ))
    );

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

revoke all on function public.sync_family_announcement_notifications() from public;
notify pgrst,'reload schema';
