-- 첨삭 슬롯별 정원과 특정 주 예외 이동의 정원 검사를 추가합니다.

create table public.correction_slot_capacities (
  teacher_profile_id uuid not null references public.profiles(id) on delete cascade,
  weekday smallint not null check(weekday between 1 and 5),
  slot_index smallint not null check(slot_index between 0 and 2),
  capacity smallint not null default 8 check(capacity between 1 and 30),
  updated_at timestamptz not null default now(),
  primary key(teacher_profile_id,weekday,slot_index)
);
alter table public.correction_slot_capacities enable row level security;
create policy "staff_read_correction_capacities" on public.correction_slot_capacities for select to authenticated using(public.is_staff());
create policy "staff_manage_own_correction_capacities" on public.correction_slot_capacities for all to authenticated using(teacher_profile_id=auth.uid() or public.current_user_role()='admin') with check(teacher_profile_id=auth.uid() or public.current_user_role()='admin');
grant select,insert,update,delete on table public.correction_slot_capacities to authenticated;

create function public.prevent_correction_capacity_below_assignments()
returns trigger language plpgsql security definer set search_path=public as $$
declare assigned integer;
begin
  select count(*) into assigned from public.correction_assignments ca where ca.teacher_profile_id=new.teacher_profile_id and ca.weekday=new.weekday and ca.slot_index=new.slot_index and (ca.valid_until is null or ca.valid_until>=current_date);
  if new.capacity<assigned then raise exception '현재 배정 %명보다 정원을 작게 설정할 수 없습니다.',assigned; end if;
  new.updated_at:=now();return new;
end $$;
create trigger correction_capacity_not_below_assignments before insert or update on public.correction_slot_capacities for each row execute function public.prevent_correction_capacity_below_assignments();

create or replace function public.prevent_correction_conflict()
returns trigger language plpgsql security definer set search_path=public as $$
declare max_capacity integer;
begin
  if exists(select 1 from public.correction_assignments ca where ca.id<>new.id and ca.student_id=new.student_id and ca.weekday=new.weekday and ca.slot_index=new.slot_index and (ca.valid_until is null or ca.valid_until>=current_date)) then
    raise exception '학생에게 같은 첨삭 시간이 이미 배정되어 있습니다.';
  end if;
  select coalesce((select c.capacity from public.correction_slot_capacities c where c.teacher_profile_id=new.teacher_profile_id and c.weekday=new.weekday and c.slot_index=new.slot_index),8) into max_capacity;
  if (select count(*) from public.correction_assignments ca where ca.id<>new.id and ca.teacher_profile_id=new.teacher_profile_id and ca.weekday=new.weekday and ca.slot_index=new.slot_index and (ca.valid_until is null or ca.valid_until>=current_date))>=max_capacity then
    raise exception '선택한 첨삭 시간은 정원 %명이 모두 찼습니다.',max_capacity;
  end if;
  return new;
end $$;

create or replace function public.prevent_correction_exception_conflict()
returns trigger language plpgsql security definer set search_path=public as $$
declare target_teacher uuid; target_student uuid; max_capacity integer; occupied integer;
begin
  select ca.teacher_profile_id,ca.student_id into target_teacher,target_student from public.correction_assignments ca where ca.id=new.assignment_id;
  if target_teacher is null then raise exception '고정 첨삭 배정을 찾을 수 없습니다.'; end if;
  if exists(select 1 from public.correction_exceptions ce join public.correction_assignments ca on ca.id=ce.assignment_id where ce.id<>new.id and ce.week_start=new.week_start and ce.weekday=new.weekday and ce.slot_index=new.slot_index and ca.student_id=target_student)
    or exists(select 1 from public.correction_assignments ca where ca.id<>new.assignment_id and ca.student_id=target_student and ca.weekday=new.weekday and ca.slot_index=new.slot_index and not exists(select 1 from public.correction_exceptions moved where moved.assignment_id=ca.id and moved.week_start=new.week_start)) then
    raise exception '학생에게 변경하려는 주의 같은 첨삭 시간이 이미 있습니다.';
  end if;
  select coalesce((select c.capacity from public.correction_slot_capacities c where c.teacher_profile_id=target_teacher and c.weekday=new.weekday and c.slot_index=new.slot_index),8) into max_capacity;
  select
    (select count(*) from public.correction_exceptions ce join public.correction_assignments ca on ca.id=ce.assignment_id where ce.id<>new.id and ce.week_start=new.week_start and ce.weekday=new.weekday and ce.slot_index=new.slot_index and ca.teacher_profile_id=target_teacher)
    +(select count(*) from public.correction_assignments ca where ca.id<>new.assignment_id and ca.teacher_profile_id=target_teacher and ca.weekday=new.weekday and ca.slot_index=new.slot_index and (ca.valid_until is null or ca.valid_until>=new.week_start) and not exists(select 1 from public.correction_exceptions moved where moved.assignment_id=ca.id and moved.week_start=new.week_start))
  into occupied;
  if occupied>=max_capacity then raise exception '변경하려는 첨삭 시간은 정원 %명이 모두 찼습니다.',max_capacity; end if;
  return new;
end $$;

create or replace function public.staff_schedule_hub()
returns jsonb language sql stable security definer set search_path=public as $$
  select case when public.is_staff() then jsonb_build_object(
    'teachers',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name) from public.profiles p where p.role in ('admin','teacher')),'[]'::jsonb),
    'students',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name) from public.students s where s.status in ('active','paused','재원','휴원')),'[]'::jsonb),
    'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.name) from public.classes c where c.active),'[]'::jsonb),
    'classSchedules',coalesce((select jsonb_agg(jsonb_build_object('id',cs.id,'classId',c.id,'className',c.name,'subject',c.subject,'color',c.color,'weekday',cs.weekday,'startTime',cs.start_time,'endTime',cs.end_time,'room',c.room,'teachers',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name) from public.class_teachers ct join public.profiles p on p.id=ct.profile_id where ct.class_id=c.id),'[]'::jsonb)) order by cs.weekday,cs.start_time) from public.class_schedules cs join public.classes c on c.id=cs.class_id),'[]'::jsonb),
    'corrections',coalesce((select jsonb_agg(jsonb_build_object('id',ca.id,'studentId',s.id,'studentName',s.name,'teacherId',p.id,'teacherName',p.display_name,'weekday',ca.weekday,'slotIndex',ca.slot_index) order by ca.weekday,ca.slot_index,s.name) from public.correction_assignments ca join public.students s on s.id=ca.student_id join public.profiles p on p.id=ca.teacher_profile_id where ca.valid_until is null or ca.valid_until>=current_date),'[]'::jsonb),
    'correctionExceptions',coalesce((select jsonb_agg(jsonb_build_object('id',ce.id,'assignmentId',ce.assignment_id,'weekStart',ce.week_start,'weekday',ce.weekday,'slotIndex',ce.slot_index,'note',ce.note) order by ce.week_start desc) from public.correction_exceptions ce join public.correction_assignments ca on ca.id=ce.assignment_id where ca.teacher_profile_id=auth.uid() or public.current_user_role()='admin'),'[]'::jsonb),
    'correctionCapacities',coalesce((select jsonb_agg(jsonb_build_object('teacherId',c.teacher_profile_id,'weekday',c.weekday,'slotIndex',c.slot_index,'capacity',c.capacity)) from public.correction_slot_capacities c),'[]'::jsonb),
    'vehicles',coalesce((select jsonb_agg(jsonb_build_object('id',vr.id,'managerId',p.id,'managerName',p.display_name,'weekday',vr.weekday,'pickupTime',vr.pickup_time,'pickupLocation',vr.pickup_location,'students',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name) from public.vehicle_boardings vb join public.students s on s.id=vb.student_id where vb.run_id=vr.id),'[]'::jsonb)) order by vr.weekday,vr.pickup_time) from public.vehicle_runs vr join public.profiles p on p.id=vr.manager_profile_id where vr.active),'[]'::jsonb)
  ) else null end
$$;

revoke all on function public.staff_schedule_hub() from public;
grant execute on function public.staff_schedule_hub() to authenticated;
