-- 자동 차량 명단 위에 요일·방향·시간을 직접 지정할 수 있는 배정

create table if not exists public.vehicle_manual_assignments (
  student_id uuid not null references public.students(id) on delete cascade,
  weekday smallint not null check (weekday between 1 and 5),
  direction text not null check (direction in ('pickup','dropoff')),
  vehicle_time time not null check (vehicle_time in (time '16:00',time '17:30',time '19:00',time '20:30')),
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (student_id,weekday,direction)
);

alter table public.vehicle_manual_assignments enable row level security;

drop policy if exists vehicle_manual_assignments_staff on public.vehicle_manual_assignments;
create policy vehicle_manual_assignments_staff
on public.vehicle_manual_assignments
for all
to authenticated
using (public.is_staff())
with check (public.is_staff());

grant select,insert,update,delete on public.vehicle_manual_assignments to authenticated;

create or replace function public.staff_manual_vehicle_data()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  if not coalesce(public.is_staff(),false) then
    raise exception '교직원만 차량 직접 배정을 확인할 수 있습니다.';
  end if;

  return jsonb_build_object(
    'students',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',s.id,'name',s.name,'school',s.school,'grade',s.grade
      ) order by s.name,s.school,s.grade)
      from public.students s
      where s.status in ('active','재원')
    ),'[]'::jsonb),
    'assignments',coalesce((
      select jsonb_agg(jsonb_build_object(
        'studentId',s.id,
        'studentName',s.name,
        'school',s.school,
        'grade',s.grade,
        'studentPhone',s.phone,
        'residence',s.residence,
        'pickupLocation',s.vehicle_pickup_location,
        'dropoffLocation',s.vehicle_dropoff_location,
        'guardians',coalesce((
          select jsonb_agg(jsonb_build_object(
            'name',g.name,'phone',g.phone,'relationship',sg.relationship,'isPrimary',sg.is_primary
          ) order by sg.is_primary desc,g.name)
          from public.student_guardians sg
          join public.guardians g on g.id=sg.guardian_id
          where sg.student_id=s.id
        ),'[]'::jsonb),
        'weekday',m.weekday,
        'direction',m.direction,
        'time',m.vehicle_time
      ) order by m.weekday,m.vehicle_time,s.name)
      from public.vehicle_manual_assignments m
      join public.students s on s.id=m.student_id
      where s.status in ('active','재원')
    ),'[]'::jsonb)
  );
end
$$;

create or replace function public.staff_save_manual_vehicle_assignment(
  p_student_id uuid,
  p_weekday smallint,
  p_direction text,
  p_time time,
  p_remove boolean default false
)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if not coalesce(public.is_staff(),false) then
    raise exception '교직원만 차량 직접 배정을 변경할 수 있습니다.';
  end if;
  if p_weekday not between 1 and 5 then raise exception '요일을 확인해 주세요.'; end if;
  if p_direction not in ('pickup','dropoff') then raise exception '등원·하원 구분을 확인해 주세요.'; end if;
  if p_time not in (time '16:00',time '17:30',time '19:00',time '20:30') then raise exception '차량 시간을 확인해 주세요.'; end if;
  if not exists(select 1 from public.students where id=p_student_id and status in ('active','재원')) then
    raise exception '재원 학생을 확인해 주세요.';
  end if;

  if p_remove then
    delete from public.vehicle_manual_assignments
    where student_id=p_student_id and weekday=p_weekday and direction=p_direction;
  else
    insert into public.vehicle_manual_assignments(student_id,weekday,direction,vehicle_time,created_by)
    values(p_student_id,p_weekday,p_direction,p_time,auth.uid())
    on conflict(student_id,weekday,direction) do update
      set vehicle_time=excluded.vehicle_time,updated_at=now(),created_by=auth.uid();

    delete from public.vehicle_schedule_exclusions
    where student_id=p_student_id and weekday=p_weekday and direction=p_direction;
  end if;
end
$$;

revoke all on function public.staff_manual_vehicle_data() from public;
revoke all on function public.staff_save_manual_vehicle_assignment(uuid,smallint,text,time,boolean) from public;
grant execute on function public.staff_manual_vehicle_data() to authenticated;
grant execute on function public.staff_save_manual_vehicle_assignment(uuid,smallint,text,time,boolean) to authenticated;

notify pgrst,'reload schema';
