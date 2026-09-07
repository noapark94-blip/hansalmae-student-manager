-- 첨삭 시험의 저장된 카테고리를 알림톡 시험 종류에 반영합니다.
create or replace function public.staff_learning_report_source(p_student_id uuid,p_from date,p_to date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare base_rows jsonb; result jsonb;
begin
  if p_from is null or p_to is null or p_to<p_from or p_to-p_from>31 then raise exception '조회 기간을 확인해 주세요.'; end if;
  if not public.can_staff_report_student(p_student_id) then raise exception '담당 학생의 리포트만 만들 수 있습니다.'; end if;
  base_rows:=public.staff_student_completed_learning_history(p_student_id,500);
  select coalesce(jsonb_agg(item order by report_date,starts_at),'[]'::jsonb) into result from (
    select jsonb_set(entry.item,'{source}',to_jsonb(case
      when entry.item->>'source' in ('makeup','extra') then entry.item->>'source'
      when exists(select 1 from public.class_makeup_attendees ma where ma.class_id=(entry.item->>'classId')::uuid and ma.student_id=p_student_id and ma.attendance_date=(entry.item->>'lessonDate')::date) then 'makeup'
      else 'regular' end)) item,
      (entry.item->>'lessonDate')::date report_date,entry.item->>'startsAt' starts_at
    from jsonb_array_elements(coalesce(base_rows,'[]'::jsonb)) entry(item)
    where (entry.item->>'lessonDate')::date between p_from and p_to
    union all
    select jsonb_build_object(
      'lessonId',r.id,'lessonDate',to_char(r.correction_date,'YYYY-MM-DD'),
      'startsAt',to_char(r.correction_date,'YYYY-MM-DD')||'T'||r.start_time::text||'+09:00',
      'classId',r.assignment_id,'className','첨삭','subject',r.subject,'source','correction','room',null,
      'teacherName',coalesce(r.recorded_by_name,'담당 선생님'),'lessonContent',coalesce(r.correction_content,''),
      'homeworkContent',coalesce(r.next_preparation,r.homework_instruction,''),'examContent',coalesce(r.exam_range,''),
      'correctionTaskStatus',r.correction_task_status,'correctionTaskFeedback',coalesce(r.correction_task_feedback,''),
      'attendance',jsonb_build_object('status',r.attendance_status,'lateMinutes',r.late_minutes,'absenceReason','','note',coalesce(r.assistant_feedback,'')),
      'homeworkResult',case when r.homework_status is null then null else jsonb_build_object('status',r.homework_status,'note',coalesce(r.homework_note,'')) end,
      'exams',case when r.exam_title is null and r.exam_score is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object(
        'id',r.id,
        'examType',case when coalesce(r.exam_range,'') like '[종류]%' then coalesce(nullif(trim(replace(split_part(r.exam_range,E'\n',1),'[종류]','')),''),'첨삭 평가') else '첨삭 평가' end,
        'examTitle',coalesce(r.exam_title,''),'score',r.exam_score,'maxScore',coalesce(r.exam_max_score,100),
        'percent',case when r.exam_score is null or coalesce(r.exam_max_score,0)<=0 then null else round(r.exam_score/r.exam_max_score*100,1) end,
        'evaluation',coalesce(r.evaluation,''),'feedback',coalesce(r.teacher_instruction,''))) end
    ) item,r.correction_date report_date,r.start_time::text starts_at
    from public.correction_reports r join public.correction_assignments ca on ca.id=r.assignment_id
    where r.student_id=p_student_id and r.correction_date between p_from and p_to and r.published
      and (public.current_user_role()='admin' or ca.teacher_profile_id=auth.uid())
  ) rows;
  return result;
end $$;

revoke all on function public.staff_learning_report_source(uuid,date,date) from public,anon;
grant execute on function public.staff_learning_report_source(uuid,date,date) to authenticated;
notify pgrst,'reload schema';
