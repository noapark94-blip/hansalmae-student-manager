-- 관리자·교사용 학생 목록에 최근 출석률을 가볍게 합산해 제공합니다.
create or replace function public.staff_student_attendance_rates(p_days integer default 30)
returns table (student_id uuid, checked_count bigint, present_count bigint, late_count bigint, absent_count bigint, attendance_rate integer)
language sql stable security definer set search_path = public
as $$
  select a.student_id,
    count(*) filter (where a.status in ('present','late','absent')),
    count(*) filter (where a.status = 'present'),
    count(*) filter (where a.status = 'late'),
    count(*) filter (where a.status = 'absent'),
    round(100.0 * count(*) filter (where a.status = 'present') / nullif(count(*) filter (where a.status in ('present','late','absent')), 0))::integer
  from public.attendance a join public.lessons l on l.id = a.lesson_id
  where public.is_staff()
    and l.lesson_date between (now() at time zone 'Asia/Seoul')::date - greatest(1, least(coalesce(p_days, 30), 365)) + 1
      and (now() at time zone 'Asia/Seoul')::date
  group by a.student_id
$$;
revoke all on function public.staff_student_attendance_rates(integer) from public;
grant execute on function public.staff_student_attendance_rates(integer) to authenticated;
notify pgrst, 'reload schema';
