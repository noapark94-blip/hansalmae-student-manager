-- 반 전체 보강 명단과 날짜별 직접 추가 명단을 모두 수업 대상자로 인정합니다.
create or replace function public.student_attends_class_on(
  p_student_id uuid,
  p_class_id uuid,
  p_date date
)
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select
    exists (
      select 1
      from public.class_makeup_attendees m
      where m.student_id = p_student_id
        and m.class_id = p_class_id
        and m.attendance_date = p_date
    )
    or exists (
      select 1
      from public.class_lesson_roster_overrides o
      where o.student_id = p_student_id
        and o.class_id = p_class_id
        and o.lesson_date = p_date
    )
    or case
      when exists (
        select 1
        from public.student_schedule_assignments
        where student_id = p_student_id
      ) then exists (
        select 1
        from public.student_schedule_assignments ssa
        join public.class_schedules cs on cs.id = ssa.class_schedule_id
        where ssa.student_id = p_student_id
          and cs.class_id = p_class_id
          and cs.weekday = extract(isodow from p_date)::smallint
      )
      else exists (
        select 1
        from public.enrollments e
        where e.student_id = p_student_id
          and e.class_id = p_class_id
          and e.status = 'active'
          and e.started_on <= p_date
          and (e.ended_on is null or e.ended_on >= p_date)
      )
    end;
$$;

revoke all on function public.student_attends_class_on(uuid,uuid,date) from public, anon;
grant execute on function public.student_attends_class_on(uuid,uuid,date) to authenticated;
