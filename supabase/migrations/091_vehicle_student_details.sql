-- 차량 명단의 학생 상세정보와 승하차 위치를 학생 기본정보에 연결합니다.

alter table public.students add column if not exists residence text;
alter table public.students add column if not exists vehicle_pickup_location text;
alter table public.students add column if not exists vehicle_dropoff_location text;

create or replace function public.staff_auto_vehicle_schedule()
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  with schedule_rows as (
    select e.student_id, cs.weekday, cs.start_time, cs.end_time,
      '정규수업'::text source, 'class'::text activity_type,
      c.name::text activity_title, c.subject::text activity_subject
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
      '첨삭'::text, 'correction'::text,
      concat(a.subject, ' 첨삭')::text, a.subject::text
    from public.correction_assignments a
    join public.students s on s.id=a.student_id
    where a.active
      and s.status in ('active','재원')
      and a.weekday between 1 and 5
      and (a.valid_from is null or a.valid_from<=current_date)
      and (a.valid_until is null or a.valid_until>=current_date)
  ), daily as (
    select student_id,weekday,min(start_time) first_start,max(end_time) last_end,
      array_agg(distinct source order by source) sources,
      jsonb_agg(jsonb_build_object(
        'type',activity_type,
        'title',activity_title,
        'subject',activity_subject,
        'startTime',start_time,
        'endTime',end_time
      ) order by start_time,end_time,activity_title) activities
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
    'studentPhone',s.phone,
    'residence',s.residence,
    'pickupLocation',s.vehicle_pickup_location,
    'dropoffLocation',s.vehicle_dropoff_location,
    'guardians',coalesce((
      select jsonb_agg(jsonb_build_object(
        'name',g.name,
        'phone',g.phone,
        'relationship',sg.relationship,
        'isPrimary',sg.is_primary
      ) order by sg.is_primary desc,g.created_at,g.name)
      from public.student_guardians sg
      join public.guardians g on g.id=sg.guardian_id
      where sg.student_id=s.id
    ),'[]'::jsonb),
    'activities',n.activities,
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

revoke all on function public.staff_auto_vehicle_schedule() from public;
grant execute on function public.staff_auto_vehicle_schedule() to authenticated;

notify pgrst,'reload schema';
