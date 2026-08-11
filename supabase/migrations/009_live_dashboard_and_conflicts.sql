-- 운영 대시보드 실시간 집계와 시간표 충돌 방지를 추가합니다.

create or replace function public.prevent_class_schedule_conflict()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_table_name = 'class_schedules' then
    if exists (
      select 1
      from public.class_teachers mine
      join public.class_teachers theirs on theirs.profile_id = mine.profile_id and theirs.class_id <> new.class_id
      join public.class_schedules other_schedule on other_schedule.class_id = theirs.class_id
      where mine.class_id = new.class_id
        and other_schedule.weekday = new.weekday
        and other_schedule.start_time < new.end_time
        and other_schedule.end_time > new.start_time
        and other_schedule.id <> new.id
    ) then
      raise exception '선택한 선생님에게 같은 시간의 다른 수업이 있습니다.';
    end if;

    if exists (
      select 1 from public.class_schedules other_schedule
      join public.classes mine_class on mine_class.id = new.class_id
      join public.classes other_class on other_class.id = other_schedule.class_id
      where other_schedule.id <> new.id
        and other_schedule.weekday = new.weekday
        and other_schedule.start_time < new.end_time
        and other_schedule.end_time > new.start_time
        and nullif(trim(mine_class.room), '') is not null
        and mine_class.room = other_class.room
    ) then
      raise exception '같은 강의실에 겹치는 수업이 있습니다.';
    end if;
  else
    if exists (
      select 1
      from public.class_schedules mine_schedule
      join public.class_teachers other_teacher on other_teacher.profile_id = new.profile_id and other_teacher.class_id <> new.class_id
      join public.class_schedules other_schedule on other_schedule.class_id = other_teacher.class_id
      where mine_schedule.class_id = new.class_id
        and mine_schedule.weekday = other_schedule.weekday
        and mine_schedule.start_time < other_schedule.end_time
        and mine_schedule.end_time > other_schedule.start_time
    ) then
      raise exception '선택한 선생님에게 같은 시간의 다른 수업이 있습니다.';
    end if;
  end if;
  return new;
end
$$;

create trigger class_schedules_prevent_conflict before insert or update on public.class_schedules
for each row execute function public.prevent_class_schedule_conflict();
create trigger class_teachers_prevent_conflict before insert or update on public.class_teachers
for each row execute function public.prevent_class_schedule_conflict();

create or replace function public.prevent_correction_conflict()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.correction_assignments ca
    where ca.id <> new.id
      and ca.weekday = new.weekday
      and ca.slot_index = new.slot_index
      and (ca.teacher_profile_id = new.teacher_profile_id or ca.student_id = new.student_id)
      and (ca.valid_until is null or ca.valid_until >= current_date)
  ) then
    raise exception '선생님 또는 학생에게 같은 첨삭 시간이 이미 배정되어 있습니다.';
  end if;
  return new;
end
$$;

create trigger correction_assignments_prevent_conflict before insert or update on public.correction_assignments
for each row execute function public.prevent_correction_conflict();

create or replace function public.prevent_correction_exception_conflict()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_teacher uuid;
  target_student uuid;
begin
  select ca.teacher_profile_id, ca.student_id into target_teacher, target_student
  from public.correction_assignments ca where ca.id = new.assignment_id;

  if exists (
    select 1
    from public.correction_exceptions ce
    join public.correction_assignments ca on ca.id = ce.assignment_id
    where ce.id <> new.id and ce.week_start = new.week_start
      and ce.weekday = new.weekday and ce.slot_index = new.slot_index
      and (ca.teacher_profile_id = target_teacher or ca.student_id = target_student)
  ) or exists (
    select 1
    from public.correction_assignments ca
    where ca.id <> new.assignment_id
      and ca.weekday = new.weekday and ca.slot_index = new.slot_index
      and (ca.teacher_profile_id = target_teacher or ca.student_id = target_student)
      and not exists (select 1 from public.correction_exceptions moved where moved.assignment_id = ca.id and moved.week_start = new.week_start)
  ) then
    raise exception '선생님 또는 학생에게 변경하려는 주의 같은 첨삭 시간이 이미 있습니다.';
  end if;
  return new;
end
$$;

create trigger correction_exceptions_prevent_conflict before insert or update on public.correction_exceptions
for each row execute function public.prevent_correction_exception_conflict();

create or replace function public.prevent_vehicle_conflict()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.vehicle_runs vr
    where vr.id <> new.id and vr.active
      and vr.manager_profile_id = new.manager_profile_id
      and vr.weekday = new.weekday
      and vr.pickup_time = new.pickup_time
  ) then
    raise exception '차량실장님에게 같은 시각의 운행이 이미 등록되어 있습니다.';
  end if;
  return new;
end
$$;

create trigger vehicle_runs_prevent_conflict before insert or update on public.vehicle_runs
for each row execute function public.prevent_vehicle_conflict();

create or replace function public.staff_save_class_schedule(
  p_schedule_id uuid,
  p_class_id uuid,
  p_weekday smallint,
  p_start_time time,
  p_end_time time,
  p_teacher_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  saved_id uuid;
  teacher_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 수업을 배정할 수 있습니다.'; end if;
  if p_start_time >= p_end_time then raise exception '종료 시간은 시작 시간보다 늦어야 합니다.'; end if;
  if coalesce(array_length(p_teacher_ids, 1), 0) = 0 then raise exception '담당 선생님을 한 명 이상 선택해 주세요.'; end if;

  -- 기존 담당자를 먼저 비우고 새 담당자를 넣어, 담당 변경과 시간 변경을 한 트랜잭션에서 검사합니다.
  delete from public.class_teachers where class_id = p_class_id;

  if p_schedule_id is null then
    insert into public.class_schedules(class_id, weekday, start_time, end_time)
    values (p_class_id, p_weekday, p_start_time, p_end_time)
    returning id into saved_id;
  else
    update public.class_schedules
    set weekday = p_weekday, start_time = p_start_time, end_time = p_end_time
    where id = p_schedule_id and class_id = p_class_id
    returning id into saved_id;
    if saved_id is null then raise exception '수업 배정을 찾을 수 없습니다.'; end if;
  end if;

  foreach teacher_id in array p_teacher_ids loop
    insert into public.class_teachers(class_id, profile_id) values (p_class_id, teacher_id);
  end loop;
  return saved_id;
end
$$;

create or replace function public.staff_save_vehicle_run(
  p_run_id uuid,
  p_manager_id uuid,
  p_weekday smallint,
  p_pickup_time time,
  p_pickup_location text,
  p_student_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  saved_id uuid;
  student_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 차량 운행을 등록할 수 있습니다.'; end if;
  if nullif(trim(p_pickup_location), '') is null then raise exception '탑승 위치를 입력해 주세요.'; end if;

  if p_run_id is null then
    insert into public.vehicle_runs(manager_profile_id, weekday, pickup_time, pickup_location)
    values (p_manager_id, p_weekday, p_pickup_time, trim(p_pickup_location))
    returning id into saved_id;
  else
    update public.vehicle_runs
    set manager_profile_id = p_manager_id, weekday = p_weekday, pickup_time = p_pickup_time, pickup_location = trim(p_pickup_location), active = true
    where id = p_run_id
    returning id into saved_id;
    if saved_id is null then raise exception '차량 운행을 찾을 수 없습니다.'; end if;
  end if;

  delete from public.vehicle_boardings where run_id = saved_id;
  foreach student_id in array coalesce(p_student_ids, array[]::uuid[]) loop
    insert into public.vehicle_boardings(run_id, student_id) values (saved_id, student_id);
  end loop;
  return saved_id;
end
$$;

revoke all on function public.staff_save_class_schedule(uuid, uuid, smallint, time, time, uuid[]) from public;
revoke all on function public.staff_save_vehicle_run(uuid, uuid, smallint, time, text, uuid[]) from public;
grant execute on function public.staff_save_class_schedule(uuid, uuid, smallint, time, time, uuid[]) to authenticated;
grant execute on function public.staff_save_vehicle_run(uuid, uuid, smallint, time, text, uuid[]) to authenticated;

create or replace function public.staff_dashboard_live()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with today as (
    select (now() at time zone 'Asia/Seoul')::date as day,
           extract(isodow from now() at time zone 'Asia/Seoul')::smallint as weekday
  ), attendance_totals as (
    select
      count(*) filter (where a.status = 'present') as present_count,
      count(*) filter (where a.status = 'late') as late_count,
      count(*) filter (where a.status = 'absent') as absent_count,
      count(*) as checked_count,
      count(*) filter (where a.makeup_required) as makeup_count
    from public.attendance a
    join public.lessons l on l.id = a.lesson_id
    join today t on t.day = l.lesson_date
  )
  select case when public.is_staff() then jsonb_build_object(
    'todayClasses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', cs.id,
        'time', cs.start_time,
        'name', c.name,
        'room', c.room,
        'color', c.color,
        'teachers', coalesce((select string_agg(p.display_name, ' · ' order by p.display_name) from public.class_teachers ct join public.profiles p on p.id = ct.profile_id where ct.class_id = c.id), '담당 미배정'),
        'enrolled', (select count(*) from public.enrollments e where e.class_id = c.id and e.status = 'active'),
        'present', (select count(*) from public.lessons l join public.attendance a on a.lesson_id = l.id where l.class_id = c.id and l.lesson_date = t.day and a.status = 'present')
      ) order by cs.start_time)
      from public.class_schedules cs
      join public.classes c on c.id = cs.class_id
      cross join today t
      where cs.weekday = t.weekday and c.active
        and (cs.valid_from is null or cs.valid_from <= t.day)
        and (cs.valid_until is null or cs.valid_until >= t.day)
    ), '[]'::jsonb),
    'attendance', (select jsonb_build_object('present', present_count, 'late', late_count, 'absent', absent_count, 'checked', checked_count, 'makeup', makeup_count) from attendance_totals),
    'weekAttendance', coalesce((
      select jsonb_agg(jsonb_build_object('weekday', daily.weekday, 'present', daily.present, 'late', daily.late, 'absent', daily.absent, 'checked', daily.checked) order by daily.weekday)
      from (
        select extract(isodow from days.day)::smallint as weekday,
               count(a.id) filter (where a.status = 'present') as present,
               count(a.id) filter (where a.status = 'late') as late,
               count(a.id) filter (where a.status = 'absent') as absent,
               count(a.id) as checked
        from today t
        cross join lateral generate_series(date_trunc('week', t.day::timestamp), date_trunc('week', t.day::timestamp) + interval '4 days', interval '1 day') days(day)
        left join public.lessons l on l.lesson_date = days.day::date
        left join public.attendance a on a.lesson_id = l.id
        group by days.day
      ) daily
    ), '[]'::jsonb)
  ) else null end
$$;

revoke all on function public.staff_dashboard_live() from public;
grant execute on function public.staff_dashboard_live() to authenticated;
