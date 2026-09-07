-- 시간표 조회 과정에서 생성된 빈 첨삭 초안은 고정 명단의 변경·삭제 이력으로 보지 않습니다.

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

    if material_change then
      delete from public.correction_reports r
      where r.assignment_id=existing.id
        and not (
          r.published
          or coalesce(r.attendance_status,'scheduled')<>'scheduled'
          or r.late_minutes is not null
          or nullif(trim(r.absence_reason),'') is not null
          or nullif(trim(r.teacher_instruction),'') is not null
          or nullif(trim(r.exam_title),'') is not null
          or nullif(trim(r.exam_range),'') is not null
          or r.exam_score is not null
          or nullif(trim(r.evaluation),'') is not null
          or nullif(trim(r.homework_instruction),'') is not null
          or nullif(trim(r.homework_status),'') is not null
          or nullif(trim(r.homework_note),'') is not null
          or nullif(trim(r.correction_content),'') is not null
          or nullif(trim(r.correction_task_status),'') is not null
          or nullif(trim(r.correction_task_feedback),'') is not null
          or nullif(trim(r.assistant_feedback),'') is not null
          or nullif(trim(r.next_preparation),'') is not null
        );
    end if;

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

  delete from public.correction_reports r
  where r.assignment_id=p_id
    and not (
      r.published
      or coalesce(r.attendance_status,'scheduled')<>'scheduled'
      or r.late_minutes is not null
      or nullif(trim(r.absence_reason),'') is not null
      or nullif(trim(r.teacher_instruction),'') is not null
      or nullif(trim(r.exam_title),'') is not null
      or nullif(trim(r.exam_range),'') is not null
      or r.exam_score is not null
      or nullif(trim(r.evaluation),'') is not null
      or nullif(trim(r.homework_instruction),'') is not null
      or nullif(trim(r.homework_status),'') is not null
      or nullif(trim(r.homework_note),'') is not null
      or nullif(trim(r.correction_content),'') is not null
      or nullif(trim(r.correction_task_status),'') is not null
      or nullif(trim(r.correction_task_feedback),'') is not null
      or nullif(trim(r.assistant_feedback),'') is not null
      or nullif(trim(r.next_preparation),'') is not null
    );

  select max(correction_date) into last_record from public.correction_reports where assignment_id=p_id;
  if last_record is null then
    delete from public.correction_assignments where id=p_id;
  else
    update public.correction_assignments
    set active=false,valid_until=greatest(valid_from,last_record,v_today-1),updated_at=now()
    where id=p_id;
  end if;
end $$;

-- 이번 배포 전에 오늘 빈 초안 때문에 남은 종료 배정을 즉시 정상화합니다.
delete from public.correction_reports r
using public.correction_assignments a
where r.assignment_id=a.id
  and not a.active
  and a.updated_at::date=(timezone('Asia/Seoul',now()))::date
  and not (
    r.published
    or coalesce(r.attendance_status,'scheduled')<>'scheduled'
    or r.late_minutes is not null
    or nullif(trim(r.absence_reason),'') is not null
    or nullif(trim(r.teacher_instruction),'') is not null
    or nullif(trim(r.exam_title),'') is not null
    or nullif(trim(r.exam_range),'') is not null
    or r.exam_score is not null
    or nullif(trim(r.evaluation),'') is not null
    or nullif(trim(r.homework_instruction),'') is not null
    or nullif(trim(r.homework_status),'') is not null
    or nullif(trim(r.homework_note),'') is not null
    or nullif(trim(r.correction_content),'') is not null
    or nullif(trim(r.correction_task_status),'') is not null
    or nullif(trim(r.correction_task_feedback),'') is not null
    or nullif(trim(r.assistant_feedback),'') is not null
    or nullif(trim(r.next_preparation),'') is not null
  );

update public.correction_assignments a
set valid_until=greatest(
      a.valid_from,
      coalesce((select max(r.correction_date) from public.correction_reports r where r.assignment_id=a.id),
               (timezone('Asia/Seoul',now()))::date-1)
    ),
    updated_at=now()
where not a.active
  and a.valid_until>=(timezone('Asia/Seoul',now()))::date
  and a.updated_at::date=(timezone('Asia/Seoul',now()))::date
  and exists(select 1 from public.correction_reports r where r.assignment_id=a.id);

delete from public.correction_assignments a
where not a.active
  and a.updated_at::date=(timezone('Asia/Seoul',now()))::date
  and not exists(select 1 from public.correction_reports r where r.assignment_id=a.id);

revoke all on function public.staff_save_correction_assignment(uuid,uuid,text,smallint,time,time,uuid,uuid,text),public.staff_delete_correction_assignment(uuid) from public,anon;
grant execute on function public.staff_save_correction_assignment(uuid,uuid,text,smallint,time,time,uuid,uuid,text),public.staff_delete_correction_assignment(uuid) to authenticated;

notify pgrst,'reload schema';
