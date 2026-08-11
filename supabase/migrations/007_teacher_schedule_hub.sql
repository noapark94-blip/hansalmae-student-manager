-- 공동담당 수업, 고정 첨삭, 차량 운행을 하나의 선생님 시간표 허브로 연결합니다.

create table public.class_teachers (
  class_id uuid not null references public.classes(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  primary key (class_id, profile_id)
);

create table public.correction_assignments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  teacher_profile_id uuid not null references public.profiles(id) on delete cascade,
  weekday smallint not null check (weekday between 1 and 5),
  slot_index smallint not null check (slot_index between 0 and 2),
  valid_from date not null default current_date,
  valid_until date,
  created_at timestamptz not null default now()
);

create table public.correction_exceptions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.correction_assignments(id) on delete cascade,
  week_start date not null,
  weekday smallint not null check (weekday between 1 and 5),
  slot_index smallint not null check (slot_index between 0 and 2),
  note text,
  unique (assignment_id, week_start)
);

create table public.vehicle_runs (
  id uuid primary key default gen_random_uuid(),
  manager_profile_id uuid not null references public.profiles(id) on delete cascade,
  weekday smallint not null check (weekday between 1 and 6),
  pickup_time time not null,
  pickup_location text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.vehicle_boardings (
  run_id uuid not null references public.vehicle_runs(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  primary key (run_id, student_id)
);

alter table public.class_teachers enable row level security;
alter table public.correction_assignments enable row level security;
alter table public.correction_exceptions enable row level security;
alter table public.vehicle_runs enable row level security;
alter table public.vehicle_boardings enable row level security;

create policy "staff_manage_class_teachers" on public.class_teachers for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "staff_read_corrections" on public.correction_assignments for select to authenticated using (public.is_staff());
create policy "assigned_teacher_insert_corrections" on public.correction_assignments for insert to authenticated with check (teacher_profile_id = auth.uid() and public.is_staff());
create policy "assigned_teacher_update_corrections" on public.correction_assignments for update to authenticated using (teacher_profile_id = auth.uid() and public.is_staff()) with check (teacher_profile_id = auth.uid() and public.is_staff());
create policy "assigned_teacher_delete_corrections" on public.correction_assignments for delete to authenticated using (teacher_profile_id = auth.uid() and public.is_staff());
create policy "staff_read_correction_exceptions" on public.correction_exceptions for select to authenticated using (public.is_staff());
create policy "assigned_teacher_insert_correction_exceptions" on public.correction_exceptions for insert to authenticated with check (exists (select 1 from public.correction_assignments ca where ca.id = assignment_id and ca.teacher_profile_id = auth.uid()));
create policy "assigned_teacher_update_correction_exceptions" on public.correction_exceptions for update to authenticated using (exists (select 1 from public.correction_assignments ca where ca.id = assignment_id and ca.teacher_profile_id = auth.uid())) with check (exists (select 1 from public.correction_assignments ca where ca.id = assignment_id and ca.teacher_profile_id = auth.uid()));
create policy "assigned_teacher_delete_correction_exceptions" on public.correction_exceptions for delete to authenticated using (exists (select 1 from public.correction_assignments ca where ca.id = assignment_id and ca.teacher_profile_id = auth.uid()));
create policy "staff_manage_vehicle_runs" on public.vehicle_runs for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "staff_manage_vehicle_boardings" on public.vehicle_boardings for all to authenticated using (public.is_staff()) with check (public.is_staff());

grant select, insert, update, delete on table public.class_teachers, public.class_schedules, public.correction_assignments, public.correction_exceptions, public.vehicle_runs, public.vehicle_boardings to authenticated;

create or replace function public.staff_schedule_hub()
returns jsonb
language sql
stable
security definer set search_path = public
as $$
  select case when public.is_staff() then jsonb_build_object(
    'teachers', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.display_name) order by p.display_name) from public.profiles p where p.role in ('admin', 'teacher')), '[]'::jsonb),
    'classSchedules', coalesce((select jsonb_agg(jsonb_build_object('id', cs.id, 'classId', c.id, 'className', c.name, 'subject', c.subject, 'color', c.color, 'weekday', cs.weekday, 'startTime', cs.start_time, 'endTime', cs.end_time, 'room', c.room, 'teachers', coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.display_name) order by p.display_name) from public.class_teachers ct join public.profiles p on p.id = ct.profile_id where ct.class_id = c.id), '[]'::jsonb)) order by cs.weekday, cs.start_time) from public.class_schedules cs join public.classes c on c.id = cs.class_id), '[]'::jsonb),
    'corrections', coalesce((select jsonb_agg(jsonb_build_object('id', ca.id, 'studentId', s.id, 'studentName', s.name, 'teacherId', p.id, 'teacherName', p.display_name, 'weekday', ca.weekday, 'slotIndex', ca.slot_index) order by ca.weekday, ca.slot_index, s.name) from public.correction_assignments ca join public.students s on s.id = ca.student_id join public.profiles p on p.id = ca.teacher_profile_id where ca.valid_until is null or ca.valid_until >= current_date), '[]'::jsonb),
    'vehicles', coalesce((select jsonb_agg(jsonb_build_object('id', vr.id, 'managerId', p.id, 'managerName', p.display_name, 'weekday', vr.weekday, 'pickupTime', vr.pickup_time, 'pickupLocation', vr.pickup_location, 'students', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name) order by s.name) from public.vehicle_boardings vb join public.students s on s.id = vb.student_id where vb.run_id = vr.id), '[]'::jsonb)) order by vr.weekday, vr.pickup_time) from public.vehicle_runs vr join public.profiles p on p.id = vr.manager_profile_id where vr.active), '[]'::jsonb)
  ) else null end
$$;

revoke all on function public.staff_schedule_hub() from public;
grant execute on function public.staff_schedule_hub() to authenticated;
