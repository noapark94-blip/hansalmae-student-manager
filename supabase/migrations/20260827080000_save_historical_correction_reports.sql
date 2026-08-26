-- 날짜 한정 과거 첨삭 배정에도 해당 날짜의 출결·시험·과제 기록을 저장할 수 있게 합니다.

create or replace function public.staff_save_correction_report_v2(
 p_assignment_id uuid,p_correction_date date,p_start_time time,p_end_time time,p_attendance_status text,p_late_minutes integer,p_absence_reason text,p_teacher_instruction text,
 p_exam_title text,p_exam_range text,p_exam_score numeric,p_exam_max_score numeric,p_evaluation text,p_homework_instruction text,p_homework_status text,
 p_homework_note text,p_correction_content text,p_assistant_feedback text,p_next_preparation text,p_published boolean
) returns uuid language plpgsql security definer set search_path=public as $$
declare a public.correction_assignments; rid uuid; pname text;
begin
 if not public.is_staff() then raise exception '교직원만 첨삭 기록을 저장할 수 있습니다.'; end if;
 select * into a from public.correction_assignments
 where id=p_assignment_id and valid_from<=p_correction_date and (valid_until is null or valid_until>=p_correction_date);
 if a.id is null then raise exception '선택한 날짜에 유효한 첨삭 배정을 찾을 수 없습니다.'; end if;
 if p_start_time>=p_end_time then raise exception '첨삭 시간을 확인해 주세요.'; end if;
 if p_attendance_status not in ('scheduled','present','late','absent') then raise exception '출석 상태를 확인해 주세요.'; end if;
 if p_attendance_status='late' and coalesce(p_late_minutes,0)<1 then raise exception '지각 시간을 입력해 주세요.'; end if;
 if p_attendance_status='absent' and nullif(trim(p_absence_reason),'') is null then raise exception '결석 사유를 입력해 주세요.'; end if;
 select display_name into pname from public.profiles where id=auth.uid();
 insert into public.correction_reports(assignment_id,student_id,correction_date,start_time,end_time,subject,attendance_status,late_minutes,absence_reason,teacher_instruction,exam_title,exam_range,exam_score,exam_max_score,evaluation,homework_instruction,homework_status,homework_note,correction_content,assistant_feedback,next_preparation,published,instruction_by,recorded_by,recorded_by_name)
 values(a.id,a.student_id,p_correction_date,p_start_time,p_end_time,a.subject,coalesce(p_attendance_status,'scheduled'),case when p_attendance_status='late' then p_late_minutes else null end,case when p_attendance_status='absent' then nullif(trim(p_absence_reason),'') else null end,nullif(trim(p_teacher_instruction),''),nullif(trim(p_exam_title),''),nullif(trim(p_exam_range),''),p_exam_score,p_exam_max_score,nullif(trim(p_evaluation),''),nullif(trim(p_homework_instruction),''),nullif(p_homework_status,''),nullif(trim(p_homework_note),''),nullif(trim(p_correction_content),''),nullif(trim(p_assistant_feedback),''),nullif(trim(p_next_preparation),''),coalesce(p_published,false),case when nullif(trim(p_teacher_instruction),'') is null then null else auth.uid() end,auth.uid(),pname)
 on conflict(assignment_id,correction_date,start_time) do update set end_time=excluded.end_time,attendance_status=excluded.attendance_status,late_minutes=excluded.late_minutes,absence_reason=excluded.absence_reason,teacher_instruction=excluded.teacher_instruction,exam_title=excluded.exam_title,exam_range=excluded.exam_range,exam_score=excluded.exam_score,exam_max_score=excluded.exam_max_score,evaluation=excluded.evaluation,homework_instruction=excluded.homework_instruction,homework_status=excluded.homework_status,homework_note=excluded.homework_note,correction_content=excluded.correction_content,assistant_feedback=excluded.assistant_feedback,next_preparation=excluded.next_preparation,published=excluded.published,instruction_by=case when excluded.teacher_instruction is distinct from public.correction_reports.teacher_instruction then auth.uid() else public.correction_reports.instruction_by end,recorded_by=auth.uid(),recorded_by_name=pname,updated_at=now()
 returning id into rid;
 return rid;
end $$;

revoke all on function public.staff_save_correction_report_v2(uuid,date,time,time,text,integer,text,text,text,text,numeric,numeric,text,text,text,text,text,text,text,boolean) from public,anon;
grant execute on function public.staff_save_correction_report_v2(uuid,date,time,time,text,integer,text,text,text,text,numeric,numeric,text,text,text,text,text,text,text,boolean) to authenticated;

notify pgrst,'reload schema';
