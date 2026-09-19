CREATE OR REPLACE FUNCTION public.staff_schedule_hub()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when public.is_staff() then jsonb_build_object(
    'teachers',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name) from public.profiles p where p.role in ('admin','teacher','sub_admin')),'[]'::jsonb),
    'students',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name) from public.students s where s.status in ('active','paused','재원','휴원')),'[]'::jsonb),
    'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.name) from public.classes c where c.active),'[]'::jsonb),
    'classSchedules',coalesce((select jsonb_agg(jsonb_build_object('id',cs.id,'classId',c.id,'className',c.name,'subject',c.subject,'color',c.color,'weekday',cs.weekday,'startTime',cs.start_time,'endTime',cs.end_time,'room',c.room,'active',c.active,'validFrom',cs.valid_from,'validUntil',cs.valid_until,'teachers',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name) from public.class_teachers ct join public.profiles p on p.id=ct.profile_id where ct.class_id=c.id),'[]'::jsonb)) order by cs.weekday,cs.start_time) from public.class_schedules cs join public.classes c on c.id=cs.class_id),'[]'::jsonb),
    'corrections',coalesce((select jsonb_agg(jsonb_build_object('id',ca.id,'studentId',s.id,'studentName',s.name,'teacherId',p.id,'teacherName',p.display_name,'weekday',ca.weekday,'slotIndex',ca.slot_index) order by ca.weekday,ca.slot_index,s.name) from public.correction_assignments ca join public.students s on s.id=ca.student_id join public.profiles p on p.id=ca.teacher_profile_id where ca.valid_until is null or ca.valid_until>=current_date),'[]'::jsonb),
    'correctionExceptions',coalesce((select jsonb_agg(jsonb_build_object('id',ce.id,'assignmentId',ce.assignment_id,'weekStart',ce.week_start,'weekday',ce.weekday,'slotIndex',ce.slot_index,'note',ce.note) order by ce.week_start desc) from public.correction_exceptions ce join public.correction_assignments ca on ca.id=ce.assignment_id where ca.teacher_profile_id=auth.uid() or public.current_user_role()='admin'),'[]'::jsonb),
    'correctionCapacities',coalesce((select jsonb_agg(jsonb_build_object('teacherId',c.teacher_profile_id,'weekday',c.weekday,'slotIndex',c.slot_index,'capacity',c.capacity)) from public.correction_slot_capacities c),'[]'::jsonb),
    'vehicles',coalesce((select jsonb_agg(jsonb_build_object('id',vr.id,'managerId',p.id,'managerName',p.display_name,'weekday',vr.weekday,'pickupTime',vr.pickup_time,'pickupLocation',vr.pickup_location,'students',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name) order by s.name) from public.vehicle_boardings vb join public.students s on s.id=vb.student_id where vb.run_id=vr.id),'[]'::jsonb)) order by vr.weekday,vr.pickup_time) from public.vehicle_runs vr join public.profiles p on p.id=vr.manager_profile_id where vr.active),'[]'::jsonb)
  ) else null end
$function$
;

CREATE OR REPLACE FUNCTION public.staff_swap_class_schedule_times(p_first_id uuid, p_second_id uuid, p_first_base jsonb, p_second_base jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  a public.class_schedules%rowtype; b public.class_schedules%rowtype;
  current_base jsonb; r public.class_schedules%rowtype;
  a_end interval; b_end interval;
begin
  if auth.uid() is null or not coalesce(public.is_staff(),false) then
    raise exception '수업 배정 권한이 없습니다.';
  end if;
  if p_first_id is null or p_second_id is null or p_first_id=p_second_id then
    raise exception '서로 다른 두 수업을 선택해 주세요.';
  end if;
  perform pg_advisory_xact_lock(hashtext('hansalmae_class_schedule_save'));
  -- Also serialize direct schedule writes while both rows are validated.
  lock table public.class_schedules in share row exclusive mode;
  perform 1 from public.classes where id in (
    select class_id from public.class_schedules where id in (p_first_id,p_second_id)
  ) order by id for update;
  select * into a from public.class_schedules where id=p_first_id for update;
  select * into b from public.class_schedules where id=p_second_id for update;
  if a.id is null or b.id is null or not exists(select 1 from public.classes where id=a.class_id and active)
    or not exists(select 1 from public.classes where id=b.class_id and active) then
    raise exception '수업이 변경되거나 삭제되었습니다. 시간표를 다시 열어 주세요.';
  end if;
  if a.valid_until<current_date or b.valid_until<current_date then
    raise exception '종료된 수업 시간은 맞바꿀 수 없습니다. 최신 시간표를 다시 열어 주세요.';
  end if;
  if a.weekday<>b.weekday then raise exception '같은 요일의 수업만 맞바꿀 수 있습니다.'; end if;
  for r in select * from public.class_schedules where id in (a.id,b.id) loop
    select jsonb_build_object('weekday',r.weekday,'startTime',to_char(r.start_time,'HH24:MI'),
      'endTime',to_char(r.end_time,'HH24:MI'),'teacherIds',
      coalesce((select jsonb_agg(profile_id::text order by profile_id) from public.class_teachers where class_id=r.class_id),'[]'::jsonb)) into current_base;
    if current_base is distinct from (case when r.id=a.id then p_first_base else p_second_base end) then
      raise exception '다른 선생님이 수업 시간 또는 담당을 변경했습니다. 최신 시간표를 확인한 뒤 다시 열어 주세요.';
    end if;
  end loop;
  if a.start_time is null or a.end_time is null or b.start_time is null or b.end_time is null
    or a.start_time>=a.end_time or b.start_time>=b.end_time then raise exception '수업의 시작·종료 시간을 확인해 주세요.'; end if;
  if a.start_time=b.start_time then raise exception '이미 시작 시간이 같은 수업입니다.'; end if;
  a_end:=(b.start_time-time '00:00')+(a.end_time-a.start_time);
  b_end:=(a.start_time-time '00:00')+(b.end_time-b.start_time);
  if a_end>=interval '24 hours' or b_end>=interval '24 hours' then
    raise exception '맞바꾼 수업이 자정을 넘습니다. 수업 시간을 확인해 주세요.';
  end if;
  update public.class_schedules set
    start_time=case when id=a.id then b.start_time else a.start_time end,
    end_time=case when id=a.id then (time '00:00'+a_end) else (time '00:00'+b_end) end
  where id in (a.id,b.id);
  -- The shared trigger checks students, teachers and rooms on the final rows.
  if exists(select 1 from public.class_schedules x join public.class_schedules y
    on y.class_id=x.class_id and y.weekday=x.weekday and y.id<>x.id
    and y.start_time<x.end_time and y.end_time>x.start_time
    and public.internal_schedule_periods_overlap(x.valid_from,x.valid_until,y.valid_from,y.valid_until) where x.id in (a.id,b.id)) then
    raise exception '클래스 시간 충돌: 맞바꾼 시간에 같은 클래스의 다른 수업이 있습니다.';
  end if;
end $function$
;
