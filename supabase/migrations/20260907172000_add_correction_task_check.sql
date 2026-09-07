-- 오늘의 첨삭 과제 수행 상태와 검사 피드백을 별도 보관합니다.

alter table public.correction_reports
  add column correction_task_status text,
  add column correction_task_feedback text,
  add constraint correction_reports_task_status_check
    check (correction_task_status is null or correction_task_status in ('completed','partial','incomplete'));

drop function public.staff_save_correction_report_v2(uuid,date,time,time,text,integer,text,text,text,text,numeric,numeric,text,text,text,text,text,text,text,boolean);

create function public.staff_save_correction_report_v2(
  p_assignment_id uuid,p_correction_date date,p_start_time time,p_end_time time,p_attendance_status text,p_late_minutes integer,
  p_absence_reason text,p_teacher_instruction text,p_exam_title text,p_exam_range text,p_exam_score numeric,p_exam_max_score numeric,
  p_evaluation text,p_homework_instruction text,p_homework_status text,p_homework_note text,p_correction_content text,
  p_assistant_feedback text,p_next_preparation text,p_published boolean,p_correction_task_status text default null,p_correction_task_feedback text default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare a public.correction_assignments; rid uuid; pname text;
begin
  if not public.is_staff() then raise exception '교직원만 첨삭 기록을 저장할 수 있습니다.'; end if;
  select * into a from public.correction_assignments where id=p_assignment_id and valid_from<=p_correction_date and (valid_until is null or valid_until>=p_correction_date);
  if a.id is null then raise exception '선택한 날짜에 유효한 첨삭 배정을 찾을 수 없습니다.'; end if;
  if p_start_time>=p_end_time then raise exception '첨삭 시간을 확인해 주세요.'; end if;
  if p_attendance_status not in ('scheduled','present','late','absent') then raise exception '출석 상태를 확인해 주세요.'; end if;
  if p_attendance_status='late' and coalesce(p_late_minutes,0)<1 then raise exception '지각 시간을 입력해 주세요.'; end if;
  if p_attendance_status='absent' and nullif(trim(p_absence_reason),'') is null then raise exception '결석 사유를 입력해 주세요.'; end if;
  if p_correction_task_status is not null and p_correction_task_status not in ('completed','partial','incomplete') then raise exception '첨삭 과제 수행 상태를 확인해 주세요.'; end if;
  select display_name into pname from public.profiles where id=auth.uid();
  insert into public.correction_reports(assignment_id,student_id,correction_date,start_time,end_time,subject,attendance_status,late_minutes,absence_reason,teacher_instruction,exam_title,exam_range,exam_score,exam_max_score,evaluation,homework_instruction,homework_status,homework_note,correction_content,correction_task_status,correction_task_feedback,assistant_feedback,next_preparation,published,instruction_by,recorded_by,recorded_by_name)
  values(a.id,a.student_id,p_correction_date,p_start_time,p_end_time,a.subject,coalesce(p_attendance_status,'scheduled'),case when p_attendance_status='late' then p_late_minutes else null end,case when p_attendance_status='absent' then nullif(trim(p_absence_reason),'') else null end,nullif(trim(p_teacher_instruction),''),nullif(trim(p_exam_title),''),nullif(trim(p_exam_range),''),p_exam_score,p_exam_max_score,nullif(trim(p_evaluation),''),nullif(trim(p_homework_instruction),''),nullif(p_homework_status,''),nullif(trim(p_homework_note),''),nullif(trim(p_correction_content),''),p_correction_task_status,nullif(trim(p_correction_task_feedback),''),nullif(trim(p_assistant_feedback),''),nullif(trim(p_next_preparation),''),coalesce(p_published,false),case when nullif(trim(p_teacher_instruction),'') is null then null else auth.uid() end,auth.uid(),pname)
  on conflict(assignment_id,correction_date,start_time) do update set end_time=excluded.end_time,attendance_status=excluded.attendance_status,late_minutes=excluded.late_minutes,absence_reason=excluded.absence_reason,teacher_instruction=excluded.teacher_instruction,exam_title=excluded.exam_title,exam_range=excluded.exam_range,exam_score=excluded.exam_score,exam_max_score=excluded.exam_max_score,evaluation=excluded.evaluation,homework_instruction=excluded.homework_instruction,homework_status=excluded.homework_status,homework_note=excluded.homework_note,correction_content=excluded.correction_content,correction_task_status=excluded.correction_task_status,correction_task_feedback=excluded.correction_task_feedback,assistant_feedback=excluded.assistant_feedback,next_preparation=excluded.next_preparation,published=excluded.published,instruction_by=case when excluded.teacher_instruction is distinct from public.correction_reports.teacher_instruction then auth.uid() else public.correction_reports.instruction_by end,recorded_by=auth.uid(),recorded_by_name=pname,updated_at=now()
  returning id into rid;
  return rid;
end $$;

create or replace function public.staff_correction_report(p_assignment_id uuid,p_date date,p_start_time time)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception '교직원만 확인할 수 있습니다.'; end if;
  return coalesce((select jsonb_build_object('id',r.id,'attendanceStatus',r.attendance_status,'lateMinutes',r.late_minutes,'absenceReason',coalesce(r.absence_reason,''),'teacherInstruction',coalesce(r.teacher_instruction,''),'examTitle',coalesce(r.exam_title,''),'examRange',coalesce(r.exam_range,''),'examScore',r.exam_score,'examMaxScore',r.exam_max_score,'evaluation',coalesce(r.evaluation,''),'homeworkInstruction',coalesce(r.homework_instruction,''),'homeworkStatus',r.homework_status,'homeworkNote',coalesce(r.homework_note,''),'correctionContent',coalesce(r.correction_content,''),'correctionTaskStatus',r.correction_task_status,'correctionTaskFeedback',coalesce(r.correction_task_feedback,''),'assistantFeedback',coalesce(r.assistant_feedback,''),'nextPreparation',coalesce(r.next_preparation,''),'published',r.published,'recordedByName',r.recorded_by_name) from public.correction_reports r where r.assignment_id=p_assignment_id and r.correction_date=p_date and r.start_time=p_start_time),'{}'::jsonb);
end $$;

create or replace function public.family_correction_reports(p_student_id uuid,p_limit integer default 20)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare role_now public.user_role; allowed_id uuid;
begin
  role_now:=public.current_user_role();
  if role_now='student' then select id into allowed_id from public.students where profile_id=auth.uid() and id=p_student_id;
  elsif role_now='guardian' then select s.id into allowed_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() and s.id=p_student_id; end if;
  if allowed_id is null then raise exception '연결된 학생의 첨삭 리포트만 확인할 수 있습니다.'; end if;
  return coalesce((select jsonb_agg(to_jsonb(q) order by q."correctionDate" desc,q."startTime" desc) from (select r.id,r.correction_date as "correctionDate",r.start_time as "startTime",r.end_time as "endTime",r.subject,r.attendance_status as "attendanceStatus",r.late_minutes as "lateMinutes",r.exam_title as "examTitle",r.exam_range as "examRange",r.exam_score as "examScore",r.exam_max_score as "examMaxScore",r.evaluation,r.homework_instruction as "homeworkInstruction",r.homework_status as "homeworkStatus",r.homework_note as "homeworkNote",r.correction_content as "correctionContent",r.correction_task_status as "correctionTaskStatus",coalesce(r.correction_task_feedback,'') as "correctionTaskFeedback",r.assistant_feedback as "assistantFeedback",r.next_preparation as "nextPreparation",r.recorded_by_name as "recordedByName" from public.correction_reports r where r.student_id=allowed_id and r.published order by r.correction_date desc,r.start_time desc limit greatest(1,least(coalesce(p_limit,20),50))) q),'[]'::jsonb);
end $$;

revoke all on function public.staff_save_correction_report_v2(uuid,date,time,time,text,integer,text,text,text,text,numeric,numeric,text,text,text,text,text,text,text,boolean,text,text) from public,anon;
revoke all on function public.staff_correction_report(uuid,date,time),public.family_correction_reports(uuid,integer) from public,anon;
grant execute on function public.staff_save_correction_report_v2(uuid,date,time,time,text,integer,text,text,text,text,numeric,numeric,text,text,text,text,text,text,text,boolean,text,text) to authenticated;
grant execute on function public.staff_correction_report(uuid,date,time),public.family_correction_reports(uuid,integer) to authenticated;
notify pgrst,'reload schema';
