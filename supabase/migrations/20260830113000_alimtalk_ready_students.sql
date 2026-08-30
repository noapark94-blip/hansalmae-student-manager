-- Daily/weekly Alimtalk candidates whose scheduled learning records are all complete.

create or replace function public.staff_alimtalk_ready_students(p_from date,p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare result jsonb;
begin
  if public.current_user_role()<>'admin' then
    raise exception '관리자만 알림톡 발송 대상을 확인할 수 있습니다.';
  end if;
  if p_from is null or p_to is null or p_to<p_from or p_to-p_from>6 then
    raise exception '발송 기간을 확인해 주세요.';
  end if;

  with recursive days as (
    select generate_series(p_from,p_to,'1 day'::interval)::date as occurrence_date
  ),
  regular_fixed as (
    select distinct e.student_id,
      'regular:'||cs.class_id::text||':'||d.occurrence_date::text||':'||cs.start_time::text as expected_key,
      cs.class_id,d.occurrence_date,cs.start_time
    from days d
    join public.class_schedules cs on cs.weekday=extract(isodow from d.occurrence_date)::smallint
      and (cs.valid_from is null or cs.valid_from<=d.occurrence_date)
      and (cs.valid_until is null or cs.valid_until>=d.occurrence_date)
    join public.classes c on c.id=cs.class_id and c.active
    join public.enrollments e on e.class_id=c.id and e.status='active'
      and e.started_on<=d.occurrence_date and (e.ended_on is null or e.ended_on>=d.occurrence_date)
    join public.students s on s.id=e.student_id and s.status in ('active','재원')
    where not exists (
      select 1 from public.schedule_exceptions x
      where x.class_id=cs.class_id and x.original_date=d.occurrence_date
        and x.kind in ('cancelled','changed','makeup')
    )
  ),
  regular_replacements as (
    select distinct e.student_id,
      'regular:'||x.class_id::text||':'||x.replacement_date::text||':'||coalesce(x.start_time,cs.start_time)::text as expected_key,
      x.class_id,x.replacement_date occurrence_date,coalesce(x.start_time,cs.start_time) start_time
    from public.schedule_exceptions x
    join public.class_schedules cs on cs.class_id=x.class_id
      and cs.weekday=extract(isodow from x.original_date)::smallint
      and (cs.valid_from is null or cs.valid_from<=x.original_date)
      and (cs.valid_until is null or cs.valid_until>=x.original_date)
    join public.classes c on c.id=x.class_id and c.active
    join public.enrollments e on e.class_id=c.id and e.status='active'
      and e.started_on<=x.replacement_date and (e.ended_on is null or e.ended_on>=x.replacement_date)
    join public.students s on s.id=e.student_id and s.status in ('active','재원')
    where x.kind in ('changed','makeup') and x.replacement_date between p_from and p_to
  ),
  class_makeups as (
    select distinct m.student_id,
      'class-makeup:'||m.class_id::text||':'||m.attendance_date::text as expected_key,
      m.class_id,m.attendance_date occurrence_date,null::time start_time
    from public.class_makeup_attendees m
    join public.students s on s.id=m.student_id and s.status in ('active','재원')
    where m.attendance_date between p_from and p_to
  ),
  expected_classes as (
    select * from regular_fixed union select * from regular_replacements union select * from class_makeups
  ),
  expected_special as (
    select a.student_id,'special:'||l.id::text expected_key
    from public.teacher_special_lessons l
    join public.teacher_special_lesson_students a on a.session_id=l.id
    join public.students s on s.id=a.student_id and s.status in ('active','재원')
    where l.lesson_date between p_from and p_to
  ),
  correction_fixed as (
    select a.student_id,'correction:'||a.id::text||':'||d.occurrence_date::text||':'||a.start_time::text expected_key,
      a.id assignment_id,d.occurrence_date,a.start_time
    from days d join public.correction_assignments a
      on a.active and a.weekday=extract(isodow from d.occurrence_date)::smallint
      and a.valid_from<=d.occurrence_date and a.valid_until>=d.occurrence_date
    join public.students s on s.id=a.student_id and s.status in ('active','재원')
    where not exists(select 1 from public.correction_schedule_exceptions x where x.assignment_id=a.id and x.original_date=d.occurrence_date and x.kind in ('move','cancel'))
  ),
  correction_changes as (
    select a.student_id,'correction:'||a.id::text||':'||x.target_date::text||':'||x.target_start_time::text expected_key,
      a.id assignment_id,x.target_date occurrence_date,x.target_start_time start_time
    from public.correction_schedule_exceptions x
    join public.correction_assignments a on a.id=x.assignment_id and a.active
    join public.students s on s.id=a.student_id and s.status in ('active','재원')
    where x.kind in ('move','extra') and x.target_date between p_from and p_to
  ),
  expected_corrections as (
    select * from correction_fixed union select * from correction_changes
  ),
  expected as (
    select student_id,expected_key,
      exists(select 1 from public.lessons l join public.attendance at on at.lesson_id=l.id and at.student_id=e.student_id where l.class_id=e.class_id and l.lesson_date=e.occurrence_date and l.status='completed') completed
    from expected_classes e
    union all
    select a.student_id,a.expected_key,
      exists(select 1 from public.teacher_special_lessons l join public.teacher_special_lesson_students ss on ss.session_id=l.id and ss.student_id=a.student_id where 'special:'||l.id::text=a.expected_key and l.status='completed' and ss.attendance_status is not null)
    from expected_special a
    union all
    select a.student_id,a.expected_key,
      exists(select 1 from public.correction_reports r where r.assignment_id=a.assignment_id and r.student_id=a.student_id and r.correction_date=a.occurrence_date and r.start_time=a.start_time and r.published and r.attendance_status<>'scheduled')
    from expected_corrections a
  ),
  readiness as (
    select student_id,count(*)::integer expected_count,count(*) filter(where completed)::integer completed_count
    from expected group by student_id
  ),
  ready as (
    select s.id,s.name,s.school,s.grade,r.expected_count,r.completed_count
    from readiness r join public.students s on s.id=r.student_id
    where r.expected_count>0 and r.completed_count=r.expected_count
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'studentId',r.id,'studentName',r.name,'school',coalesce(r.school,''),'grade',coalesce(r.grade,''),
    'expectedCount',r.expected_count,'completedCount',r.completed_count,
    'lessons',public.staff_learning_report_source(r.id,p_from,p_to),
    'recipient',public.staff_alimtalk_recipient(r.id)
  ) order by r.name),'[]'::jsonb) into result from ready r;
  return result;
end $$;

revoke all on function public.staff_alimtalk_ready_students(date,date) from public,anon;
grant execute on function public.staff_alimtalk_ready_students(date,date) to authenticated;
notify pgrst,'reload schema';
