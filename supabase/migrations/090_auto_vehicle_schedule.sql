-- 수업·첨삭 일정에서 자동 생성되는 월~금 차량 명단과 방향별 제외 설정

create table if not exists public.vehicle_schedule_exclusions (
  student_id uuid not null references public.students(id) on delete cascade,
  weekday smallint not null check (weekday between 1 and 5),
  direction text not null check (direction in ('pickup','dropoff')),
  created_by uuid references public.profiles(id) on delete set null default auth.uid(),
  created_at timestamptz not null default now(),
  primary key (student_id, weekday, direction)
);

alter table public.vehicle_schedule_exclusions enable row level security;

drop policy if exists vehicle_schedule_exclusions_staff on public.vehicle_schedule_exclusions;
create policy vehicle_schedule_exclusions_staff
on public.vehicle_schedule_exclusions
for all
to authenticated
using (public.is_staff())
with check (public.is_staff());

grant select, insert, update, delete on public.vehicle_schedule_exclusions to authenticated;

create or replace function public.staff_auto_vehicle_schedule()
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  with schedule_rows as (
    select e.student_id, cs.weekday, cs.start_time, cs.end_time, '정규수업'::text source
    from public.enrollments e
    join public.class_schedules cs on cs.class_id=e.class_id
    join public.classes c on c.id=e.class_id
    join public.students s on s.id=e.student_id
    where e.status::text='active'
      and c.active
      and s.status in ('active','재원')
      and cs.weekday between 1 and 5
      and (cs.valid_from is null or cs.valid_from<=current_date)
      and (cs.valid_until is null or cs.valid_until>=current_date)
      and (e.started_on is null or e.started_on<=current_date)
      and (e.ended_on is null or e.ended_on>=current_date)
    union all
    select a.student_id, a.weekday,
      coalesce(a.start_time,case a.slot_index when 0 then time '17:30' when 1 then time '19:00' when 2 then time '20:30' end),
      coalesce(a.end_time,case a.slot_index when 0 then time '19:00' when 1 then time '20:30' when 2 then time '22:00' end),
      '첨삭'::text
    from public.correction_assignments a
    join public.students s on s.id=a.student_id
    where a.active
      and s.status in ('active','재원')
      and a.weekday between 1 and 5
      and (a.valid_from is null or a.valid_from<=current_date)
      and (a.valid_until is null or a.valid_until>=current_date)
  ), daily as (
    select student_id,weekday,min(start_time) first_start,max(end_time) last_end,
      array_agg(distinct source order by source) sources
    from schedule_rows
    where start_time is not null and end_time is not null
    group by student_id,weekday
  ), normalized as (
    select d.*,
      case when d.first_start in (time '16:00',time '17:30',time '19:00',time '20:30') then d.first_start end pickup_time,
      case when d.last_end in (time '16:00',time '17:30',time '19:00',time '20:30') then d.last_end end dropoff_time
    from daily d
  )
  select case when public.is_staff() then coalesce(jsonb_agg(jsonb_build_object(
    'studentId',s.id,
    'studentName',s.name,
    'school',s.school,
    'grade',s.grade,
    'weekday',n.weekday,
    'pickupTime',n.pickup_time,
    'dropoffTime',n.dropoff_time,
    'sources',to_jsonb(n.sources),
    'pickupExcluded',pe.student_id is not null,
    'dropoffExcluded',de.student_id is not null
  ) order by n.weekday,n.pickup_time nulls last,n.dropoff_time nulls last,s.name),'[]'::jsonb) else null end
  from normalized n
  join public.students s on s.id=n.student_id
  left join public.vehicle_schedule_exclusions pe on pe.student_id=n.student_id and pe.weekday=n.weekday and pe.direction='pickup'
  left join public.vehicle_schedule_exclusions de on de.student_id=n.student_id and de.weekday=n.weekday and de.direction='dropoff'
  where n.pickup_time is not null or n.dropoff_time is not null
$$;

create or replace function public.staff_set_vehicle_schedule_exclusion(
  p_student_id uuid,
  p_weekday smallint,
  p_direction text,
  p_excluded boolean
)
returns void
language plpgsql
security definer
set search_path=public
as $$
begin
  if not coalesce(public.is_staff(),false) then
    raise exception '교직원만 차량 이용 여부를 변경할 수 있습니다.';
  end if;
  if p_weekday not between 1 and 5 then
    raise exception '차량 운행 요일을 확인해 주세요.';
  end if;
  if p_direction not in ('pickup','dropoff') then
    raise exception '등원·하원 구분을 확인해 주세요.';
  end if;
  if not exists(select 1 from public.students where id=p_student_id and status in ('active','재원')) then
    raise exception '재원 학생을 확인해 주세요.';
  end if;

  if p_excluded then
    insert into public.vehicle_schedule_exclusions(student_id,weekday,direction,created_by)
    values(p_student_id,p_weekday,p_direction,auth.uid())
    on conflict(student_id,weekday,direction) do nothing;
  else
    delete from public.vehicle_schedule_exclusions
    where student_id=p_student_id and weekday=p_weekday and direction=p_direction;
  end if;
end
$$;

revoke all on function public.staff_auto_vehicle_schedule() from public;
revoke all on function public.staff_set_vehicle_schedule_exclusion(uuid,smallint,text,boolean) from public;
grant execute on function public.staff_auto_vehicle_schedule() to authenticated;
grant execute on function public.staff_set_vehicle_schedule_exclusion(uuid,smallint,text,boolean) to authenticated;

notify pgrst,'reload schema';