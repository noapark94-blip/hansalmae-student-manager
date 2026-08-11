-- 날짜별 수업 출결 조회와 안전한 출결 입력을 추가합니다.

create or replace function public.staff_attendance_board(p_date date)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case when public.is_staff() then coalesce((
    select jsonb_agg(jsonb_build_object(
      'scheduleId', cs.id,
      'classId', c.id,
      'className', c.name,
      'subject', c.subject,
      'room', c.room,
      'color', c.color,
      'startTime', cs.start_time,
      'endTime', cs.end_time,
      'students', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', s.id,
          'name', s.name,
          'status', a.status,
          'note', a.note,
          'makeupRequired', coalesce(a.makeup_required, false)
        ) order by s.name)
        from public.enrollments e
        join public.students s on s.id = e.student_id
        left join public.lessons l on l.class_id = c.id and l.lesson_date = p_date and l.starts_at = ((p_date + cs.start_time) at time zone 'Asia/Seoul')
        left join public.attendance a on a.lesson_id = l.id and a.student_id = s.id
        where e.class_id = c.id and e.status = 'active'
          and e.started_on <= p_date and (e.ended_on is null or e.ended_on >= p_date)
      ), '[]'::jsonb)
    ) order by cs.start_time)
    from public.class_schedules cs
    join public.classes c on c.id = cs.class_id
    where c.active
      and cs.weekday = extract(isodow from p_date)::smallint
      and (cs.valid_from is null or cs.valid_from <= p_date)
      and (cs.valid_until is null or cs.valid_until >= p_date)
      and not exists (
        select 1 from public.schedule_exceptions se
        where se.class_id = c.id and se.original_date = p_date and se.kind = 'cancelled'
      )
  ), '[]'::jsonb) else null end
$$;

create or replace function public.staff_save_attendance(
  p_schedule_id uuid,
  p_date date,
  p_student_id uuid,
  p_status public.attendance_status,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  target_schedule public.class_schedules%rowtype;
  target_class public.classes%rowtype;
  target_lesson_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 출결을 입력할 수 있습니다.'; end if;
  select * into target_schedule from public.class_schedules where id = p_schedule_id;
  if target_schedule.id is null or target_schedule.weekday <> extract(isodow from p_date)::smallint then raise exception '선택한 날짜의 수업을 찾을 수 없습니다.'; end if;
  select * into target_class from public.classes where id = target_schedule.class_id and active;
  if target_class.id is null then raise exception '운영 중인 클래스를 찾을 수 없습니다.'; end if;
  if not exists (select 1 from public.enrollments e where e.class_id = target_class.id and e.student_id = p_student_id and e.status = 'active' and e.started_on <= p_date and (e.ended_on is null or e.ended_on >= p_date)) then raise exception '이 수업의 재원생이 아닙니다.'; end if;

  insert into public.lessons(class_id, lesson_date, starts_at, ends_at, room)
  values (target_class.id, p_date, ((p_date + target_schedule.start_time) at time zone 'Asia/Seoul'), ((p_date + target_schedule.end_time) at time zone 'Asia/Seoul'), target_class.room)
  on conflict (class_id, starts_at) do update set ends_at = excluded.ends_at, room = excluded.room
  returning id into target_lesson_id;

  insert into public.attendance(lesson_id, student_id, status, checked_at, note, makeup_required)
  values (target_lesson_id, p_student_id, p_status, now(), nullif(trim(p_note), ''), p_status = 'absent')
  on conflict (lesson_id, student_id) do update
  set status = excluded.status, checked_at = excluded.checked_at, note = excluded.note, makeup_required = excluded.makeup_required;
end
$$;

create or replace function public.staff_mark_class_present(p_schedule_id uuid, p_date date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  student_record record;
begin
  if not public.is_staff() then raise exception '교직원만 출결을 입력할 수 있습니다.'; end if;
  for student_record in
    select e.student_id, (
      select a.note from public.lessons l join public.attendance a on a.lesson_id = l.id
      where l.class_id = cs.class_id and l.starts_at = ((p_date + cs.start_time) at time zone 'Asia/Seoul') and a.student_id = e.student_id
    ) as existing_note
    from public.class_schedules cs
    join public.enrollments e on e.class_id = cs.class_id
    where cs.id = p_schedule_id and cs.weekday = extract(isodow from p_date)::smallint
      and e.status = 'active' and e.started_on <= p_date and (e.ended_on is null or e.ended_on >= p_date)
  loop
    perform public.staff_save_attendance(p_schedule_id, p_date, student_record.student_id, 'present', student_record.existing_note);
  end loop;
end
$$;

revoke all on function public.staff_attendance_board(date) from public;
revoke all on function public.staff_save_attendance(uuid, date, uuid, public.attendance_status, text) from public;
revoke all on function public.staff_mark_class_present(uuid, date) from public;
grant execute on function public.staff_attendance_board(date) to authenticated;
grant execute on function public.staff_save_attendance(uuid, date, uuid, public.attendance_status, text) to authenticated;
grant execute on function public.staff_mark_class_present(uuid, date) to authenticated;
