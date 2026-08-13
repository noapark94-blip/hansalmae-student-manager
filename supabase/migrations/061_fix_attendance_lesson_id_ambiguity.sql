-- 출석 저장 함수의 지역 변수와 attendance.lesson_id 열 이름 충돌을 제거합니다.

create or replace function public.staff_save_class_attendance(
  p_class_id uuid,
  p_date date,
  p_student_id uuid,
  p_status public.attendance_status,
  p_late_minutes integer default null,
  p_absence_reason text default null,
  p_note text default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lesson_id uuid;
begin
  v_lesson_id := public.staff_save_class_day(
    p_class_id,
    p_date,
    null,
    null,
    null
  );

  if not exists (
    select 1
    from public.enrollments e
    where e.class_id = p_class_id
      and e.student_id = p_student_id
      and e.status = 'active'
  ) then
    raise exception '이 클래스의 수강생이 아닙니다.';
  end if;

  if p_status = 'late' and coalesce(p_late_minutes, 0) < 1 then
    raise exception '지각 시간을 입력해 주세요.';
  end if;

  if p_status = 'absent' and nullif(trim(p_absence_reason), '') is null then
    raise exception '결석 사유를 입력해 주세요.';
  end if;

  insert into public.attendance as attendance_record (
    lesson_id,
    student_id,
    status,
    checked_at,
    note,
    makeup_required,
    late_minutes,
    absence_reason
  ) values (
    v_lesson_id,
    p_student_id,
    p_status,
    now(),
    nullif(trim(p_note), ''),
    p_status = 'absent',
    case when p_status = 'late' then p_late_minutes end,
    case when p_status = 'absent' then nullif(trim(p_absence_reason), '') end
  )
  on conflict (lesson_id, student_id)
  do update set
    status = excluded.status,
    checked_at = now(),
    note = excluded.note,
    makeup_required = excluded.makeup_required,
    late_minutes = excluded.late_minutes,
    absence_reason = excluded.absence_reason;
end;
$$;

revoke all on function public.staff_save_class_attendance(
  uuid,
  date,
  uuid,
  public.attendance_status,
  integer,
  text,
  text
) from public;

grant execute on function public.staff_save_class_attendance(
  uuid,
  date,
  uuid,
  public.attendance_status,
  integer,
  text,
  text
) to authenticated;

notify pgrst, 'reload schema';
