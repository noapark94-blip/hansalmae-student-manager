-- 시간표 허브의 실제 등록·수정 화면과 계정/담당자 규칙을 지원합니다.

create or replace function public.require_staff_profile()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_profile_id uuid;
begin
  target_profile_id := case tg_table_name
    when 'class_teachers' then new.profile_id
    when 'vehicle_runs' then new.manager_profile_id
    else new.teacher_profile_id
  end;

  if not exists (
    select 1 from public.profiles p
    where p.id = target_profile_id and p.role in ('admin', 'teacher')
  ) then
    raise exception '로그인한 관리자 또는 선생님 계정만 담당자로 배정할 수 있습니다.';
  end if;
  return new;
end
$$;

create trigger class_teachers_require_staff before insert or update on public.class_teachers
for each row execute function public.require_staff_profile();
create trigger corrections_require_staff before insert or update on public.correction_assignments
for each row execute function public.require_staff_profile();
create trigger vehicle_runs_require_staff before insert or update on public.vehicle_runs
for each row execute function public.require_staff_profile();

create or replace function public.staff_schedule_hub()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case when public.is_staff() then jsonb_build_object(
    'teachers', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.display_name) order by p.display_name) from public.profiles p where p.role in ('admin', 'teacher')), '[]'::jsonb),
    'students', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) order by s.name) from public.students s where s.status in ('active', 'paused')), '[]'::jsonb),
    'classes', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by c.name) from public.classes c where c.active), '[]'::jsonb),
    'classSchedules', coalesce((select jsonb_agg(jsonb_build_object('id', cs.id, 'classId', c.id, 'className', c.name, 'subject', c.subject, 'color', c.color, 'weekday', cs.weekday, 'startTime', cs.start_time, 'endTime', cs.end_time, 'room', c.room, 'teachers', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.display_name) order by p.display_name) from public.class_teachers ct join public.profiles p on p.id = ct.profile_id where ct.class_id = c.id), '[]'::jsonb)) order by cs.weekday, cs.start_time) from public.class_schedules cs join public.classes c on c.id = cs.class_id), '[]'::jsonb),
    'corrections', coalesce((select jsonb_agg(jsonb_build_object('id', ca.id, 'studentId', s.id, 'studentName', s.name, 'teacherId', p.id, 'teacherName', p.display_name, 'weekday', ca.weekday, 'slotIndex', ca.slot_index) order by ca.weekday, ca.slot_index, s.name) from public.correction_assignments ca join public.students s on s.id = ca.student_id join public.profiles p on p.id = ca.teacher_profile_id where ca.valid_until is null or ca.valid_until >= current_date), '[]'::jsonb),
    'correctionExceptions', coalesce((select jsonb_agg(jsonb_build_object('id', ce.id, 'assignmentId', ce.assignment_id, 'weekStart', ce.week_start, 'weekday', ce.weekday, 'slotIndex', ce.slot_index, 'note', ce.note) order by ce.week_start desc) from public.correction_exceptions ce join public.correction_assignments ca on ca.id = ce.assignment_id where ca.teacher_profile_id = auth.uid()), '[]'::jsonb),
    'vehicles', coalesce((select jsonb_agg(jsonb_build_object('id', vr.id, 'managerId', p.id, 'managerName', p.display_name, 'weekday', vr.weekday, 'pickupTime', vr.pickup_time, 'pickupLocation', vr.pickup_location, 'students', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) order by s.name) from public.vehicle_boardings vb join public.students s on s.id = vb.student_id where vb.run_id = vr.id), '[]'::jsonb)) order by vr.weekday, vr.pickup_time) from public.vehicle_runs vr join public.profiles p on p.id = vr.manager_profile_id where vr.active), '[]'::jsonb)
  ) else null end
$$;

revoke all on function public.staff_schedule_hub() from public;
grant execute on function public.staff_schedule_hub() to authenticated;
