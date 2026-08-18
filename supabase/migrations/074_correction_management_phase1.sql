-- 한살매 첨삭 관리 1차: 고정 첨삭 배정 + 주별 변경/취소/추가 + 학생 개인 시간표 연동

create table if not exists public.correction_assignments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  subject text not null check (subject in ('국어','영어','수학')),
  weekday smallint not null check (weekday between 1 and 7),
  start_time time not null,
  end_time time not null,
  tutor_profile_id uuid references public.profiles(id) on delete set null,
  supervisor_profile_id uuid references public.profiles(id) on delete set null,
  note text,
  active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(student_id, subject, weekday, start_time)
);

create table if not exists public.correction_schedule_exceptions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.correction_assignments(id) on delete cascade,
  original_date date not null,
  kind text not null check (kind in ('move','cancel','extra')),
  target_date date,
  target_start_time time,
  target_end_time time,
  note text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (kind='cancel' and target_date is null)
    or (kind in ('move','extra') and target_date is not null and target_start_time is not null and target_end_time is not null)
  )
);

create unique index if not exists correction_one_move_or_cancel
on public.correction_schedule_exceptions(assignment_id, original_date)
where kind in ('move','cancel');

alter table public.correction_assignments enable row level security;
alter table public.correction_schedule_exceptions enable row level security;

drop policy if exists correction_staff_assignments on public.correction_assignments;
create policy correction_staff_assignments on public.correction_assignments for all to authenticated
using (public.is_staff()) with check (public.is_staff());

drop policy if exists correction_staff_exceptions on public.correction_schedule_exceptions;
create policy correction_staff_exceptions on public.correction_schedule_exceptions for all to authenticated
using (public.is_staff()) with check (public.is_staff());

grant select,insert,update,delete on public.correction_assignments, public.correction_schedule_exceptions to authenticated;

create or replace function public.correction_management_board(p_anchor date default current_date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_start date; v_end date; result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 첨삭 관리를 확인할 수 있습니다.'; end if;
  v_start:=p_anchor-(extract(isodow from p_anchor)::int-1);
  v_end:=v_start+6;
  select jsonb_build_object(
    'weekStart',to_char(v_start,'YYYY-MM-DD'),
    'students',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade) order by s.name) from public.students s where s.status in ('active','재원')),'[]'::jsonb),
    'staff',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name) from public.profiles p where p.role in ('admin','teacher')),'[]'::jsonb),
    'assignments',coalesce((select jsonb_agg(jsonb_build_object(
      'id',a.id,'studentId',a.student_id,'studentName',s.name,'school',s.school,'grade',s.grade,'subject',a.subject,
      'weekday',a.weekday,'startTime',a.start_time,'endTime',a.end_time,'tutorId',a.tutor_profile_id,'tutorName',tp.display_name,
      'supervisorId',a.supervisor_profile_id,'supervisorName',sp.display_name,'note',a.note
    ) order by a.weekday,a.start_time,a.subject,s.name)
    from public.correction_assignments a join public.students s on s.id=a.student_id
    left join public.profiles tp on tp.id=a.tutor_profile_id left join public.profiles sp on sp.id=a.supervisor_profile_id
    where a.active),'[]'::jsonb),
    'exceptions',coalesce((select jsonb_agg(jsonb_build_object(
      'id',e.id,'assignmentId',e.assignment_id,'originalDate',to_char(e.original_date,'YYYY-MM-DD'),'kind',e.kind,
      'targetDate',case when e.target_date is null then null else to_char(e.target_date,'YYYY-MM-DD') end,
      'targetStartTime',e.target_start_time,'targetEndTime',e.target_end_time,'note',e.note
    ) order by e.original_date,e.created_at)
    from public.correction_schedule_exceptions e
    where e.original_date between v_start and v_end or e.target_date between v_start and v_end),'[]'::jsonb)
  ) into result;
  return result;
end $$;

create or replace function public.staff_save_correction_assignment(
  p_id uuid,p_student_id uuid,p_subject text,p_weekday smallint,p_start_time time,p_end_time time,
  p_tutor_profile_id uuid,p_supervisor_profile_id uuid,p_note text
) returns uuid language plpgsql security definer set search_path=public as $$
declare result uuid;
begin
  if not public.is_staff() then raise exception '교직원만 첨삭 배정을 저장할 수 있습니다.'; end if;
  if p_subject not in ('국어','영어','수학') then raise exception '첨삭 과목을 확인해 주세요.'; end if;
  if p_weekday not between 1 and 7 or p_start_time>=p_end_time then raise exception '첨삭 요일과 시간을 확인해 주세요.'; end if;
  if not exists(select 1 from public.students where id=p_student_id and status in ('active','재원')) then raise exception '재원 학생을 선택해 주세요.'; end if;
  if p_id is null then
    insert into public.correction_assignments(student_id,subject,weekday,start_time,end_time,tutor_profile_id,supervisor_profile_id,note,created_by)
    values(p_student_id,p_subject,p_weekday,p_start_time,p_end_time,p_tutor_profile_id,p_supervisor_profile_id,nullif(trim(p_note),''),auth.uid()) returning id into result;
  else
    update public.correction_assignments set student_id=p_student_id,subject=p_subject,weekday=p_weekday,start_time=p_start_time,end_time=p_end_time,
      tutor_profile_id=p_tutor_profile_id,supervisor_profile_id=p_supervisor_profile_id,note=nullif(trim(p_note),''),updated_at=now()
    where id=p_id returning id into result;
    if result is null then raise exception '첨삭 배정을 찾을 수 없습니다.'; end if;
  end if;
  return result;
end $$;

create or replace function public.staff_delete_correction_assignment(p_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception '교직원만 첨삭 배정을 삭제할 수 있습니다.'; end if;
  delete from public.correction_assignments where id=p_id;
end $$;

create or replace function public.staff_save_correction_exception(
  p_id uuid,p_assignment_id uuid,p_original_date date,p_kind text,p_target_date date,p_target_start_time time,p_target_end_time time,p_note text
) returns uuid language plpgsql security definer set search_path=public as $$
declare result uuid;
begin
  if not public.is_staff() then raise exception '교직원만 첨삭 일정 변경을 저장할 수 있습니다.'; end if;
  if p_kind not in ('move','cancel','extra') then raise exception '일정 변경 유형을 확인해 주세요.'; end if;
  if not exists(select 1 from public.correction_assignments where id=p_assignment_id and active) then raise exception '고정 첨삭 배정을 찾을 수 없습니다.'; end if;
  if p_kind in ('move','extra') and (p_target_date is null or p_target_start_time is null or p_target_end_time is null or p_target_start_time>=p_target_end_time) then raise exception '변경할 날짜와 시간을 확인해 주세요.'; end if;
  if p_id is null then
    insert into public.correction_schedule_exceptions(assignment_id,original_date,kind,target_date,target_start_time,target_end_time,note,created_by)
    values(p_assignment_id,p_original_date,p_kind,case when p_kind='cancel' then null else p_target_date end,case when p_kind='cancel' then null else p_target_start_time end,case when p_kind='cancel' then null else p_target_end_time end,nullif(trim(p_note),''),auth.uid()) returning id into result;
  else
    update public.correction_schedule_exceptions set kind=p_kind,target_date=case when p_kind='cancel' then null else p_target_date end,
      target_start_time=case when p_kind='cancel' then null else p_target_start_time end,target_end_time=case when p_kind='cancel' then null else p_target_end_time end,
      note=nullif(trim(p_note),''),updated_at=now() where id=p_id returning id into result;
  end if;
  return result;
end $$;

create or replace function public.staff_delete_correction_exception(p_id uuid)
returns void language plpgsql security definer set search_path=public as $$;
begin
  if not public.is_staff() then raise exception '교직원만 첨삭 일정 변경을 삭제할 수 있습니다.'; end if;
  delete from public.correction_schedule_exceptions where id=p_id;
end $$;

create or replace function public.staff_correction_student_timetables()
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not public.is_staff() then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'studentId',s.id,
    'rows',coalesce((select jsonb_agg(jsonb_build_object(
      'id','correction-'||a.id::text,'weekday',a.weekday,'startTime',a.start_time,'endTime',a.end_time,
      'className',a.subject||' 첨삭','subject','첨삭','color','#922D61','room',null,
      'teachers',coalesce((select jsonb_agg(x) from (select distinct jsonb_build_object('id',p.id,'name',p.display_name) x from public.profiles p where p.id in (a.tutor_profile_id,a.supervisor_profile_id)) q),'[]'::jsonb)
    ) order by a.weekday,a.start_time,a.subject) from public.correction_assignments a where a.student_id=s.id and a.active),'[]'::jsonb)
  ) order by s.name) from public.students s where s.status in ('active','재원')),'[]'::jsonb);
end $$;

revoke all on function public.correction_management_board(date),public.staff_save_correction_assignment(uuid,uuid,text,smallint,time,time,uuid,uuid,text),public.staff_delete_correction_assignment(uuid),public.staff_save_correction_exception(uuid,uuid,date,text,date,time,time,text),public.staff_delete_correction_exception(uuid),public.staff_correction_student_timetables() from public;
grant execute on function public.correction_management_board(date),public.staff_save_correction_assignment(uuid,uuid,text,smallint,time,time,uuid,uuid,text),public.staff_delete_correction_assignment(uuid),public.staff_save_correction_exception(uuid,uuid,date,text,date,time,time,text),public.staff_delete_correction_exception(uuid),public.staff_correction_student_timetables() to authenticated;

notify pgrst,'reload schema';
