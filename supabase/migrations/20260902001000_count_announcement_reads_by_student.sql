-- 공지 확인 현황은 학생 계정과 학부모 계정을 중복 집계하지 않고 학생(가족) 단위로 계산합니다.

create or replace function public.staff_announcement_read_overview()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 공지 확인 현황을 볼 수 있습니다.'; end if;

  with target_students as (
    select distinct a.id announcement_id, s.id student_id
    from public.announcements a
    join public.students s on s.status in ('active','재원')
      and (
        a.audience='all'
        or (a.audience='student' and s.id=a.student_id)
        or (a.audience='class' and exists(
          select 1 from public.enrollments e
          where e.student_id=s.id and e.class_id=a.class_id and e.status='active'
        ))
      )
    where a.published_at is not null
  ), student_reads as (
    select ts.announcement_id, ts.student_id,
      exists (
        select 1
        from public.announcement_read_receipts rr
        where rr.announcement_id=ts.announcement_id
          and (
            rr.profile_id=(select s.profile_id from public.students s where s.id=ts.student_id)
            or rr.profile_id in (
              select g.profile_id
              from public.student_guardians sg
              join public.guardians g on g.id=sg.guardian_id
              where sg.student_id=ts.student_id and g.profile_id is not null
            )
          )
      ) as has_read
    from target_students ts
  ), counts as (
    select a.id,
      count(sr.student_id)::integer recipient_count,
      count(sr.student_id) filter (where sr.has_read)::integer read_count
    from public.announcements a
    left join student_reads sr on sr.announcement_id=a.id
    group by a.id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'announcementId',a.id,
    'recipientCount',coalesce(c.recipient_count,0),
    'readCount',coalesce(c.read_count,0),
    'unreadCount',greatest(coalesce(c.recipient_count,0)-coalesce(c.read_count,0),0)
  ) order by coalesce(a.published_at,a.created_at) desc),'[]'::jsonb)
  into result
  from public.announcements a left join counts c on c.id=a.id;
  return result;
end $$;

revoke all on function public.staff_announcement_read_overview() from public;
grant execute on function public.staff_announcement_read_overview() to authenticated;
notify pgrst,'reload schema';
