-- Additive, read-only RPCs. No operational rows or existing APIs are changed.
-- Family ownership is resolved before reading any student data.
create or replace function public.family_student_context(p_student_id uuid default null, p_include_schedule boolean default false)
returns jsonb language plpgsql stable security definer set search_path = public
as $function$
declare viewer_role public.user_role; selected_id uuid; result jsonb;
begin
  selected_id := public.internal_family_student_id(p_student_id);
  viewer_role := public.current_user_role();
  select jsonb_build_object(
    'role',viewer_role,
    'children',case when viewer_role='guardian' then coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade) order by sg.is_primary desc,s.name) from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid()),'[]'::jsonb) else coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade)) from public.students s where s.id=selected_id),'[]'::jsonb) end,
    'selectedStudent',(select jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade) from public.students s where s.id=selected_id),
    'weekClasses',case when p_include_schedule then coalesce((select jsonb_agg(jsonb_build_object('id',cs.id,'name',c.name,'subject',c.subject,'room',c.room,'color',c.color,'weekday',cs.weekday,'startTime',cs.start_time,'endTime',cs.end_time,'teachers',coalesce((select string_agg(p.display_name,' · ' order by p.display_name) from public.class_teachers ct join public.profiles p on p.id=ct.profile_id where ct.class_id=c.id),'')) order by cs.weekday,cs.start_time) from public.enrollments e join public.classes c on c.id=e.class_id join public.class_schedules cs on cs.class_id=c.id where e.student_id=selected_id and e.status='active' and c.active and (not exists(select 1 from public.student_schedule_assignments a where a.student_id=selected_id) or exists(select 1 from public.student_schedule_assignments a where a.student_id=selected_id and a.class_schedule_id=cs.id)) and (cs.valid_from is null or cs.valid_from<=current_date) and (cs.valid_until is null or cs.valid_until>=current_date)),'[]'::jsonb) else '[]'::jsonb end
  ) into result;
  return result;
end $function$;
revoke all on function public.family_student_context(uuid,boolean) from public,anon,authenticated;
grant execute on function public.family_student_context(uuid,boolean) to authenticated;

-- A bounded date interval replaces the 30/50-record caps for daily/weekly/monthly summaries.
create or replace function public.family_summary_snapshot(p_student_id uuid, p_start_date date, p_end_date date)
returns jsonb language plpgsql stable security definer set search_path = public
as $function$
declare selected_id uuid; lesson_rows jsonb; correction_rows jsonb; context_row jsonb;
begin
  selected_id := public.internal_family_student_id(p_student_id);
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date or p_end_date-p_start_date > 31 then
    raise exception '조회 기간은 최대 32일이며 시작일과 종료일이 필요합니다.';
  end if;
  context_row := public.family_student_context(selected_id);
  if selected_id is null then
    return jsonb_build_object('dashboard',context_row,'lessons','[]'::jsonb,'corrections','[]'::jsonb);
  end if;
  select coalesce(jsonb_agg(item order by lesson_date desc,starts_at desc),'[]'::jsonb) into lesson_rows
  from (
    select jsonb_build_object(
      'lessonId',l.id,'lessonDate',to_char(l.lesson_date,'YYYY-MM-DD'),'startsAt',l.starts_at,'classId',c.id,'className',c.name,'subject',c.subject,'room',coalesce(l.room,c.room),'teacherName',coalesce(tp.display_name,'담당 선생님'),
      'lessonContent',coalesce(nullif(trim(hr.lesson_content),''),l.lesson_content,''),'classNotice',coalesce(n.content,''),'homeworkContent',coalesce(hr.assigned_homework,l.homework_content,''),'examContent',coalesce(l.exam_content,''),
      'attendance',case when a.id is null then null else jsonb_build_object('status',a.status,'lateMinutes',a.late_minutes,'absenceReason',coalesce(a.absence_reason,''),'note',coalesce(a.note,'')) end,
      'homeworkResult',case when hr.id is null then null else jsonb_build_object('status',coalesce(hr.inspection_status,hr.status,''),'note',coalesce(hr.inspection_note,hr.note,'')) end,
      'exams',coalesce((select jsonb_agg(jsonb_build_object('id',er.id,'examType',coalesce(er.exam_type,''),'examTitle',coalesce(er.exam_title,''),'score',er.score,'maxScore',coalesce(er.max_score,100),'percent',case when er.score is null or coalesce(er.max_score,0)<=0 then null else round(er.score/er.max_score*100,1) end,'evaluation',coalesce(er.evaluation,''),'feedback',coalesce(er.feedback,'')) order by er.created_at,er.id) from public.lesson_exam_results er where er.lesson_id=l.id and er.student_id=selected_id),'[]'::jsonb)
    ) item,l.lesson_date,l.starts_at::text starts_at
    from public.lessons l join public.classes c on c.id=l.class_id 
    left join public.profiles tp on tp.id=l.teacher_profile_id left join public.attendance a on a.lesson_id=l.id and a.student_id=selected_id left join public.lesson_homework_results hr on hr.lesson_id=l.id and hr.student_id=selected_id
    left join public.class_daily_notices n on n.class_id=l.class_id and n.notice_date=l.lesson_date
    where l.status='completed' and a.id is not null
      and l.lesson_date between p_start_date and least(p_end_date,current_date)
      union all
      select jsonb_build_object(
        'lessonId',l.id,'lessonDate',to_char(l.lesson_date,'YYYY-MM-DD'),
        'startsAt',to_char(l.lesson_date,'YYYY-MM-DD')||'T'||l.starts_at::text||'+09:00',
        'classId',l.id,'className',case when l.kind='makeup' then '개별 보강' else '추가수업' end,
        'subject',case when l.kind='makeup' then '보강' else '추가수업' end,
        'mainSubject',coalesce(sub.name,''),
        'room',l.room,'teacherName',coalesce(p.display_name,'담당 선생님'),
        'lessonContent',coalesce(a.lesson_content,''),'homeworkContent',coalesce(a.assigned_homework,''),
        'examContent','',
        'attendance',case when a.attendance_status is null then null else jsonb_build_object(
          'status',a.attendance_status,'lateMinutes',a.late_minutes,
          'absenceReason',coalesce(a.absence_reason,''),'note','') end,
        'homeworkResult',case when a.inspection_status is null then null else jsonb_build_object(
          'status',a.inspection_status,'note',coalesce(a.inspection_note,'')) end,
        'exams',coalesce((select jsonb_agg(jsonb_build_object(
          'id',e.id,'examType',coalesce(e.exam_type,''),'examTitle',coalesce(e.exam_title,''),
          'score',e.score,'maxScore',coalesce(e.max_score,100),
          'percent',case when e.score is null or coalesce(e.max_score,0)<=0 then null else round(e.score/e.max_score*100,1) end,
          'evaluation',coalesce(e.evaluation,''),'feedback',coalesce(e.evaluation,'')
        )) from public.teacher_special_lesson_exam_results e
          where e.session_id=l.id and e.student_id=selected_id),'[]'::jsonb)
      ) item,l.lesson_date,l.starts_at::text starts_at
      from public.teacher_special_lessons l
      join public.teacher_special_lesson_students a on a.session_id=l.id and a.student_id=selected_id
      left join public.academy_subjects sub on sub.id=l.subject_id
      left join public.profiles p on p.id=l.teacher_profile_id
      where l.status='completed' and l.lesson_date between p_start_date and least(p_end_date,current_date)
  ) reports;
  select coalesce((select jsonb_agg(to_jsonb(q) order by q."correctionDate" desc,q."startTime" desc) from (select r.id,r.correction_date as "correctionDate",r.start_time as "startTime",r.end_time as "endTime",r.subject,r.attendance_status as "attendanceStatus",r.late_minutes as "lateMinutes",r.exam_title as "examTitle",r.exam_range as "examRange",r.exam_score as "examScore",r.exam_max_score as "examMaxScore",r.evaluation,r.homework_instruction as "homeworkInstruction",r.homework_status as "homeworkStatus",r.homework_note as "homeworkNote",r.correction_content as "correctionContent",r.correction_task_status as "correctionTaskStatus",coalesce(r.correction_task_feedback,'') as "correctionTaskFeedback",r.assistant_feedback as "assistantFeedback",r.next_preparation as "nextPreparation",r.recorded_by_name as "recordedByName" from public.correction_reports r where r.student_id=selected_id and r.published and r.correction_date between p_start_date and least(p_end_date,current_date) order by r.correction_date desc,r.start_time desc) q),'[]'::jsonb) into correction_rows;
  return jsonb_build_object('dashboard',context_row,'lessons',lesson_rows,'corrections',correction_rows);
end $function$;
revoke all on function public.family_summary_snapshot(uuid,date,date) from public,anon,authenticated;
grant execute on function public.family_summary_snapshot(uuid,date,date) to authenticated;
