-- 기존 공식 첨삭 시간표(007~024)와 신규 첨삭 관리(074~)를 안전하게 공존시킵니다.
-- 기존 데이터는 보존하고 신규 관리에 필요한 컬럼만 확장합니다. 정원 제한은 제거합니다.

alter table public.correction_assignments add column if not exists subject text;
alter table public.correction_assignments add column if not exists start_time time;
alter table public.correction_assignments add column if not exists end_time time;
alter table public.correction_assignments add column if not exists tutor_profile_id uuid references public.profiles(id) on delete set null;
alter table public.correction_assignments add column if not exists supervisor_profile_id uuid references public.profiles(id) on delete set null;
alter table public.correction_assignments add column if not exists note text;
alter table public.correction_assignments add column if not exists active boolean not null default true;
alter table public.correction_assignments add column if not exists created_by uuid references public.profiles(id) on delete set null;
alter table public.correction_assignments add column if not exists updated_at timestamptz not null default now();

-- 신규 첨삭 관리는 주말까지 사용하므로 기존 평일 전용 제약을 확장합니다.
alter table public.correction_assignments drop constraint if exists correction_assignments_weekday_check;
alter table public.correction_assignments add constraint correction_assignments_weekday_check check (weekday between 1 and 7);
alter table public.correction_assignments alter column slot_index drop not null;

-- 기존 공식 첨삭 배정은 그대로 살리고 화면 표시용 시간/담당 값만 보완합니다.
update public.correction_assignments
set start_time = case slot_index when 0 then time '17:30' when 1 then time '19:00' when 2 then time '20:30' else start_time end,
    end_time = case slot_index when 0 then time '19:00' when 1 then time '20:30' when 2 then time '22:00' else end_time end,
    tutor_profile_id = coalesce(tutor_profile_id,teacher_profile_id),
    active = case when valid_until is null or valid_until>=current_date then true else false end
where subject is null;

do $$ begin
  if not exists(select 1 from pg_constraint where conname='correction_assignments_subject_check_v2') then
    alter table public.correction_assignments add constraint correction_assignments_subject_check_v2 check(subject is null or subject in ('국어','영어','수학'));
  end if;
  if not exists(select 1 from pg_constraint where conname='correction_assignments_time_check_v2') then
    alter table public.correction_assignments add constraint correction_assignments_time_check_v2 check(start_time is null or end_time is null or start_time<end_time);
  end if;
end $$;

create unique index if not exists correction_management_assignment_unique
on public.correction_assignments(student_id,subject,weekday,start_time)
where subject is not null and active;

-- 예전 정원 기능은 더 이상 운영하지 않습니다. 테이블은 기록 보존용으로 남기되 강제 제한만 제거합니다.
drop trigger if exists correction_capacity_not_below_assignments on public.correction_slot_capacities;

create or replace function public.prevent_correction_conflict()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  -- 신규 첨삭 관리 행(slot_index=null)은 신규 RPC/예외 구조에서 관리합니다.
  if new.slot_index is null then return new; end if;
  -- 기존 공식 시간표에서는 같은 학생의 같은 시간 중복만 막고 정원 제한은 두지 않습니다.
  if exists(
    select 1 from public.correction_assignments ca
    where ca.id<>new.id and ca.student_id=new.student_id
      and ca.weekday=new.weekday and ca.slot_index=new.slot_index
      and (ca.valid_until is null or ca.valid_until>=current_date)
  ) then raise exception '학생에게 같은 첨삭 시간이 이미 배정되어 있습니다.'; end if;
  return new;
end $$;

-- 신규 첨삭 관리 저장은 기존 공식 시간표의 필수 컬럼도 안전하게 채우되,
-- slot_index=null로 두어 두 화면의 데이터가 섞이지 않도록 합니다.
create or replace function public.staff_save_correction_assignment(
  p_id uuid,p_student_id uuid,p_subject text,p_weekday smallint,p_start_time time,p_end_time time,
  p_tutor_profile_id uuid,p_supervisor_profile_id uuid,p_note text
) returns uuid language plpgsql security definer set search_path=public as $$
declare result uuid; legacy_teacher uuid;
begin
  if not public.is_staff() then raise exception '교직원만 첨삭 배정을 저장할 수 있습니다.'; end if;
  if p_subject not in ('국어','영어','수학') then raise exception '첨삭 과목을 확인해 주세요.'; end if;
  if p_weekday not between 1 and 7 or p_start_time>=p_end_time then raise exception '첨삭 요일과 시간을 확인해 주세요.'; end if;
  if not exists(select 1 from public.students where id=p_student_id and status in ('active','재원')) then raise exception '재원 학생을 선택해 주세요.'; end if;
  legacy_teacher:=coalesce(p_tutor_profile_id,auth.uid());
  if p_id is null then
    insert into public.correction_assignments(
      student_id,teacher_profile_id,weekday,slot_index,valid_from,subject,start_time,end_time,
      tutor_profile_id,supervisor_profile_id,note,active,created_by,updated_at
    ) values(
      p_student_id,legacy_teacher,p_weekday,null,current_date,p_subject,p_start_time,p_end_time,
      p_tutor_profile_id,p_supervisor_profile_id,nullif(trim(p_note),''),true,auth.uid(),now()
    ) returning id into result;
  else
    update public.correction_assignments set
      student_id=p_student_id,teacher_profile_id=legacy_teacher,weekday=p_weekday,slot_index=null,
      subject=p_subject,start_time=p_start_time,end_time=p_end_time,tutor_profile_id=p_tutor_profile_id,
      supervisor_profile_id=p_supervisor_profile_id,note=nullif(trim(p_note),''),active=true,updated_at=now()
    where id=p_id and subject is not null returning id into result;
    if result is null then raise exception '첨삭 관리 배정을 찾을 수 없습니다.'; end if;
  end if;
  return result;
end $$;

create or replace function public.staff_delete_correction_assignment(p_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception '교직원만 첨삭 배정을 삭제할 수 있습니다.'; end if;
  delete from public.correction_assignments where id=p_id and subject is not null;
end $$;

create or replace function public.correction_management_board_v2(p_anchor text default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_anchor date:=coalesce(nullif(p_anchor,'')::date,current_date);v_start date;v_end date;
begin
  if not public.is_staff() then raise exception '교직원만 첨삭 관리를 확인할 수 있습니다.'; end if;
  v_start:=v_anchor-(extract(isodow from v_anchor)::int-1);v_end:=v_start+6;
  return jsonb_build_object(
    'weekStart',to_char(v_start,'YYYY-MM-DD'),
    'students',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade) order by s.name) from public.students s where s.status in ('active','재원')),'[]'::jsonb),
    'staff',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name) from public.profiles p where p.role::text in ('admin','teacher')),'[]'::jsonb),
    'assignments',coalesce((select jsonb_agg(jsonb_build_object(
      'id',a.id,'studentId',a.student_id,'studentName',s.name,'school',s.school,'grade',s.grade,'subject',a.subject,
      'weekday',a.weekday,'startTime',to_char(a.start_time,'HH24:MI:SS'),'endTime',to_char(a.end_time,'HH24:MI:SS'),
      'tutorId',a.tutor_profile_id,'tutorName',tp.display_name,'supervisorId',a.supervisor_profile_id,'supervisorName',sp.display_name,'note',a.note
    ) order by a.weekday,a.start_time,a.subject,s.name)
      from public.correction_assignments a join public.students s on s.id=a.student_id
      left join public.profiles tp on tp.id=a.tutor_profile_id left join public.profiles sp on sp.id=a.supervisor_profile_id
      where a.active and a.subject is not null and a.start_time is not null and a.end_time is not null),'[]'::jsonb),
    'exceptions',coalesce((select jsonb_agg(jsonb_build_object(
      'id',e.id,'assignmentId',e.assignment_id,'originalDate',to_char(e.original_date,'YYYY-MM-DD'),'kind',e.kind,
      'targetDate',case when e.target_date is null then null else to_char(e.target_date,'YYYY-MM-DD') end,
      'targetStartTime',case when e.target_start_time is null then null else to_char(e.target_start_time,'HH24:MI:SS') end,
      'targetEndTime',case when e.target_end_time is null then null else to_char(e.target_end_time,'HH24:MI:SS') end,'note',e.note
    ) order by e.original_date,e.created_at)
      from public.correction_schedule_exceptions e join public.correction_assignments a on a.id=e.assignment_id
      where a.subject is not null and (e.original_date between v_start and v_end or (e.target_date is not null and e.target_date between v_start and v_end))),'[]'::jsonb)
  );
end $$;

create or replace function public.correction_management_board(p_anchor date default current_date)
returns jsonb language sql stable security definer set search_path=public as $$
  select public.correction_management_board_v2(coalesce(p_anchor,current_date)::text)
$$;

create or replace function public.correction_day_board(p_date text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_date date:=coalesce(nullif(p_date,'')::date,current_date);v_weekday int:=extract(isodow from coalesce(nullif(p_date,'')::date,current_date))::int;
begin
  if not public.is_staff() then raise exception '교직원만 첨삭 진행 명단을 확인할 수 있습니다.'; end if;
  return jsonb_build_object(
    'assignments',coalesce((select jsonb_agg(jsonb_build_object(
      'id',a.id,'studentId',a.student_id,'studentName',s.name,'school',s.school,'grade',s.grade,'subject',a.subject,
      'weekday',a.weekday,'startTime',to_char(a.start_time,'HH24:MI:SS'),'endTime',to_char(a.end_time,'HH24:MI:SS'),
      'tutorName',tp.display_name,'supervisorName',sp.display_name,'note',a.note
    ) order by a.start_time,a.subject,s.name)
      from public.correction_assignments a join public.students s on s.id=a.student_id
      left join public.profiles tp on tp.id=a.tutor_profile_id left join public.profiles sp on sp.id=a.supervisor_profile_id
      where a.active and a.subject is not null and a.weekday=v_weekday),'[]'::jsonb),
    'exceptions',coalesce((select jsonb_agg(jsonb_build_object(
      'id',e.id,'assignmentId',e.assignment_id,'originalDate',to_char(e.original_date,'YYYY-MM-DD'),'kind',e.kind,
      'targetDate',case when e.target_date is null then null else to_char(e.target_date,'YYYY-MM-DD') end,
      'targetStartTime',case when e.target_start_time is null then null else to_char(e.target_start_time,'HH24:MI:SS') end,
      'targetEndTime',case when e.target_end_time is null then null else to_char(e.target_end_time,'HH24:MI:SS') end,'note',e.note
    ) order by e.created_at)
      from public.correction_schedule_exceptions e join public.correction_assignments a on a.id=e.assignment_id
      where a.subject is not null and (e.original_date=v_date or e.target_date=v_date)),'[]'::jsonb)
  );
end $$;

-- 학생 개인 시간표에는 신규 첨삭 관리 배정만 합칩니다. 기존 공식 시간표 데이터는 중복 표시하지 않습니다.
create or replace function public.staff_student_weekly_timetables()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_week_start date;
begin
  if not public.is_staff() then raise exception '교직원만 학생 시간표를 확인할 수 있습니다.'; end if;
  v_week_start:=current_date-(extract(isodow from current_date)::int-1);
  return coalesce((select jsonb_agg(jsonb_build_object('studentId',s.id,'rows',coalesce((
    select jsonb_agg(r.row_data order by r.weekday,r.start_time,r.sort_order,r.title) from (
      select cs.weekday::int weekday,cs.start_time,0 sort_order,c.name title,jsonb_build_object(
        'id',cs.id::text,'weekday',cs.weekday,'startTime',cs.start_time,'endTime',cs.end_time,'className',c.name,
        'subject',c.subject,'color',c.color,'room',c.room,'teachers',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name) from public.class_teachers ct join public.profiles p on p.id=ct.profile_id where ct.class_id=c.id),'[]'::jsonb)
      ) row_data
      from public.enrollments e join public.classes c on c.id=e.class_id join public.class_schedules cs on cs.class_id=c.id
      where e.student_id=s.id and e.status='active' and c.active
        and (cs.valid_from is null or cs.valid_from<=current_date) and (cs.valid_until is null or cs.valid_until>=current_date)
        and (not exists(select 1 from public.student_schedule_assignments z where z.student_id=s.id) or exists(select 1 from public.student_schedule_assignments z where z.student_id=s.id and z.class_schedule_id=cs.id))
      union all
      select a.weekday::int,a.start_time,1,a.subject||' 첨삭',jsonb_build_object(
        'id','correction-'||a.id::text,'weekday',a.weekday,'startTime',a.start_time,'endTime',a.end_time,'className',a.subject||' 첨삭','subject','첨삭','color','#922D61','room',null,'teachers',public.correction_timetable_staff(a.tutor_profile_id,a.supervisor_profile_id)
      ) from public.correction_assignments a
      where a.student_id=s.id and a.active and a.subject is not null
        and not exists(select 1 from public.correction_schedule_exceptions x where x.assignment_id=a.id and x.original_date=v_week_start+(a.weekday-1) and x.kind in ('move','cancel'))
      union all
      select extract(isodow from x.target_date)::int,x.target_start_time,1,a.subject||' 첨삭',jsonb_build_object(
        'id','correction-move-'||x.id::text,'weekday',extract(isodow from x.target_date)::int,'startTime',x.target_start_time,'endTime',x.target_end_time,'className',a.subject||' 첨삭 · 변경','subject','첨삭','color','#922D61','room',null,'teachers',public.correction_timetable_staff(a.tutor_profile_id,a.supervisor_profile_id)
      ) from public.correction_assignments a join public.correction_schedule_exceptions x on x.assignment_id=a.id
      where a.student_id=s.id and a.active and a.subject is not null and x.kind='move' and x.original_date=v_week_start+(a.weekday-1) and x.target_date between v_week_start and v_week_start+6
      union all
      select extract(isodow from x.target_date)::int,x.target_start_time,2,a.subject||' 첨삭',jsonb_build_object(
        'id','correction-extra-'||x.id::text,'weekday',extract(isodow from x.target_date)::int,'startTime',x.target_start_time,'endTime',x.target_end_time,'className',a.subject||' 첨삭 · 추가','subject','첨삭','color','#922D61','room',null,'teachers',public.correction_timetable_staff(a.tutor_profile_id,a.supervisor_profile_id)
      ) from public.correction_assignments a join public.correction_schedule_exceptions x on x.assignment_id=a.id
      where a.student_id=s.id and a.active and a.subject is not null and x.kind='extra' and x.target_date between v_week_start and v_week_start+6
    ) r
  ),'[]'::jsonb)) order by s.name) from public.students s),'[]'::jsonb);
end $$;

revoke all on function public.correction_management_board_v2(text),public.correction_management_board(date),public.correction_day_board(text),public.staff_save_correction_assignment(uuid,uuid,text,smallint,time,time,uuid,uuid,text),public.staff_delete_correction_assignment(uuid) from public;
grant execute on function public.correction_management_board_v2(text),public.correction_management_board(date),public.correction_day_board(text),public.staff_save_correction_assignment(uuid,uuid,text,smallint,time,time,uuid,uuid,text),public.staff_delete_correction_assignment(uuid),public.staff_student_weekly_timetables() to authenticated;
notify pgrst,'reload schema';
