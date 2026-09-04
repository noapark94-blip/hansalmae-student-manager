-- 기록이 없는 고정 첨삭 일정은 즉시 수정·삭제하고,
-- 기록이 있는 일정만 과거 이력으로 보존합니다.

create or replace function public.staff_save_correction_assignment(
  p_id uuid,p_student_id uuid,p_subject text,p_weekday smallint,p_start_time time,p_end_time time,
  p_tutor_profile_id uuid,p_supervisor_profile_id uuid,p_note text
) returns uuid language plpgsql security definer set search_path=public as $$
declare
  result uuid;
  legacy_teacher uuid;
  existing public.correction_assignments;
  v_today date:=(timezone('Asia/Seoul',now()))::date;
  material_change boolean;
  has_history boolean;
begin
  if not public.is_staff() then raise exception '교직원만 첨삭 배정을 저장할 수 있습니다.'; end if;
  if p_subject not in ('국어','영어','수학') then raise exception '첨삭 과목을 확인해 주세요.'; end if;
  if p_weekday not between 1 and 7 or p_start_time>=p_end_time then raise exception '첨삭 요일과 시간을 확인해 주세요.'; end if;
  if not exists(select 1 from public.students where id=p_student_id and status in ('active','재원')) then raise exception '재원 학생을 선택해 주세요.'; end if;
  legacy_teacher:=coalesce(p_tutor_profile_id,auth.uid());

  if p_id is null then
    insert into public.correction_assignments(student_id,teacher_profile_id,weekday,slot_index,valid_from,subject,start_time,end_time,tutor_profile_id,supervisor_profile_id,note,active,created_by,updated_at)
    values(p_student_id,legacy_teacher,p_weekday,null,v_today,p_subject,p_start_time,p_end_time,p_tutor_profile_id,p_supervisor_profile_id,nullif(trim(p_note),''),true,auth.uid(),now()) returning id into result;
  else
    select * into existing from public.correction_assignments where id=p_id and subject is not null for update;
    if existing.id is null then raise exception '첨삭 관리 배정을 찾을 수 없습니다.'; end if;

    material_change:=existing.student_id is distinct from p_student_id or existing.subject is distinct from p_subject or existing.weekday is distinct from p_weekday
      or existing.start_time is distinct from p_start_time or existing.end_time is distinct from p_end_time
      or existing.tutor_profile_id is distinct from p_tutor_profile_id or existing.supervisor_profile_id is distinct from p_supervisor_profile_id;
    has_history:=exists(select 1 from public.correction_reports where assignment_id=existing.id);

    if material_change and existing.valid_from<v_today and has_history then
      update public.correction_assignments
      set active=false,valid_until=greatest(valid_from,v_today-1),updated_at=now()
      where id=existing.id;
      insert into public.correction_assignments(student_id,teacher_profile_id,weekday,slot_index,valid_from,subject,start_time,end_time,tutor_profile_id,supervisor_profile_id,note,active,created_by,updated_at)
      values(p_student_id,legacy_teacher,p_weekday,null,v_today,p_subject,p_start_time,p_end_time,p_tutor_profile_id,p_supervisor_profile_id,nullif(trim(p_note),''),true,auth.uid(),now()) returning id into result;
    else
      update public.correction_assignments
      set student_id=p_student_id,teacher_profile_id=legacy_teacher,weekday=p_weekday,slot_index=null,subject=p_subject,start_time=p_start_time,end_time=p_end_time,
        tutor_profile_id=p_tutor_profile_id,supervisor_profile_id=p_supervisor_profile_id,note=nullif(trim(p_note),''),active=true,valid_until=null,updated_at=now()
      where id=existing.id returning id into result;
    end if;
  end if;
  return result;
end $$;

create or replace function public.staff_delete_correction_assignment(p_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare
  a public.correction_assignments;
  v_today date:=(timezone('Asia/Seoul',now()))::date;
  last_record date;
begin
  if not public.is_staff() then raise exception '교직원만 첨삭 배정을 종료할 수 있습니다.'; end if;
  select * into a from public.correction_assignments where id=p_id and subject is not null for update;
  if a.id is null then raise exception '첨삭 배정을 찾을 수 없습니다.'; end if;

  select max(correction_date) into last_record from public.correction_reports where assignment_id=p_id;
  if last_record is null then
    delete from public.correction_assignments where id=p_id;
  else
    update public.correction_assignments
    set active=false,valid_until=greatest(valid_from,last_record,v_today-1),updated_at=now()
    where id=p_id;
  end if;
end $$;

create or replace function public.correction_management_board_v2(p_anchor text default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_anchor date:=coalesce(nullif(p_anchor,'')::date,(timezone('Asia/Seoul',now()))::date);v_start date;v_end date;
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
      'active',a.active,'validFrom',to_char(a.valid_from,'YYYY-MM-DD'),'validUntil',case when a.valid_until is null then null else to_char(a.valid_until,'YYYY-MM-DD') end,
      'isDateOverride',(not a.active and a.valid_until is not null and (timezone('Asia/Seoul',a.created_at))::date>a.valid_until),
      'tutorId',a.tutor_profile_id,'tutorName',tp.display_name,'supervisorId',a.supervisor_profile_id,'supervisorName',sp.display_name,'note',a.note
    ) order by a.weekday,a.start_time,a.subject,s.name)
      from public.correction_assignments a join public.students s on s.id=a.student_id
      left join public.profiles tp on tp.id=a.tutor_profile_id left join public.profiles sp on sp.id=a.supervisor_profile_id
      where a.subject is not null and a.start_time is not null and a.end_time is not null
        and (
          (a.valid_from<=v_end and (a.valid_until is null or a.valid_until>=v_start))
          or exists(select 1 from public.correction_schedule_exceptions x where x.assignment_id=a.id and (x.original_date between v_start and v_end or x.target_date between v_start and v_end))
        )),'[]'::jsonb),
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

revoke all on function public.staff_save_correction_assignment(uuid,uuid,text,smallint,time,time,uuid,uuid,text),public.staff_delete_correction_assignment(uuid),public.correction_management_board_v2(text) from public,anon;
grant execute on function public.staff_save_correction_assignment(uuid,uuid,text,smallint,time,time,uuid,uuid,text),public.staff_delete_correction_assignment(uuid),public.correction_management_board_v2(text) to authenticated;

notify pgrst,'reload schema';
