CREATE OR REPLACE FUNCTION public.internal_alimtalk_report_sources(p_student_ids uuid[], p_from date, p_to date)
 RETURNS TABLE(student_id uuid, lessons jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with regular_rows as (
 select a.student_id,jsonb_build_object(
      'lessonId', l.id,
      'lessonDate', to_char(l.lesson_date, 'YYYY-MM-DD'),
      'startsAt', l.starts_at,
      'classId', c.id,
      'className', c.name,
      'subject', c.subject,
      'room', coalesce(l.room, c.room),
      'teacherName', coalesce(tp.display_name, '담당 선생님'),
      'source', case when exists(select 1 from public.class_makeup_attendees ma where ma.student_id=a.student_id and ma.class_id=c.id and ma.attendance_date=l.lesson_date) then 'makeup' else 'regular' end,
      'lessonContent', coalesce(hr.lesson_content, ''),
      'homeworkContent', coalesce(hr.assigned_homework, ''),
      'examContent', coalesce(l.exam_content, ''),
      'attendance', case when a.id is null then null else jsonb_build_object(
        'status', a.status,
        'lateMinutes', a.late_minutes,
        'absenceReason', coalesce(a.absence_reason, ''),
        'note', coalesce(a.note, '')
      ) end,
      'homeworkResult', case
        when hr.id is null or (
          nullif(trim(coalesce(hr.status, '')), '') is null
          and nullif(trim(coalesce(hr.note, '')), '') is null
          and nullif(trim(coalesce(hr.inspection_status, '')), '') is null
          and nullif(trim(coalesce(hr.inspection_note, '')), '') is null
        ) then null
        else jsonb_build_object(
          'status', coalesce(nullif(hr.inspection_status, ''), hr.status, ''),
          'note', coalesce(nullif(hr.inspection_note, ''), hr.note, '')
        )
      end,
      'exams', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', er.id,
          'examType', coalesce(er.exam_type, ''),
          'examTitle', coalesce(er.exam_title, ''),
          'score', er.score,
          'maxScore', coalesce(er.max_score, 100),
          'percent', case when er.score is null or coalesce(er.max_score, 0) <= 0 then null else round(er.score / er.max_score * 100, 1) end,
          'evaluation', coalesce(er.evaluation, ''),
          'feedback', coalesce(er.feedback, '')
        ) order by er.created_at, er.id)
        from (
          -- Match staff_class_exam_results -> exams[0], the editable exam.
          -- Later duplicate inserts are historical artifacts, not additional exams.
          select current_exam.* from public.lesson_exam_results current_exam
          where current_exam.lesson_id=l.id and current_exam.student_id=a.student_id
          order by current_exam.created_at,current_exam.id limit 1
        ) er
        where (
            er.score is not null
            or nullif(trim(coalesce(er.exam_type, '')), '') is not null
            or nullif(trim(coalesce(er.exam_title, '')), '') is not null
            or nullif(trim(coalesce(er.evaluation, '')), '') is not null
            or nullif(trim(coalesce(er.feedback, '')), '') is not null
          )
      ), '[]'::jsonb)
    ) item,l.lesson_date,l.starts_at::text sort_time,
 row_number() over(partition by a.student_id order by l.lesson_date desc,l.starts_at desc) rn
 from public.lessons l join public.classes c on c.id=l.class_id
 join public.attendance a on a.lesson_id=l.id and a.student_id=any(p_student_ids)
 left join public.profiles tp on tp.id=l.teacher_profile_id
 left join public.lesson_homework_results hr on hr.lesson_id=l.id and hr.student_id=a.student_id
 where l.status='completed' and l.lesson_date between p_from and p_to and l.lesson_date<=current_date
), special_rows as (
 select a.student_id,jsonb_build_object(
      'lessonId',l.id,'lessonDate',to_char(l.lesson_date,'YYYY-MM-DD'),'startsAt',to_char(l.lesson_date,'YYYY-MM-DD')||'T'||l.starts_at::text||'+09:00',
      'classId',l.id,'className',case when l.kind='makeup' then '개별 보강' else '추가수업' end,
      'subject',coalesce(s.name,'과목 미지정'),'source',case when l.kind='additional' then 'extra' else l.kind end,'room',l.room,'teacherName',coalesce(p.display_name,'담당 선생님'),
      'lessonContent',coalesce(a.lesson_content,''),'homeworkContent',coalesce(a.assigned_homework,''),'examContent','',
      'attendance',case when a.attendance_status is null then null else jsonb_build_object('status',a.attendance_status,'lateMinutes',a.late_minutes,'absenceReason',coalesce(a.absence_reason,''),'note','') end,
      'homeworkResult',case when a.inspection_status is null then null else jsonb_build_object('status',a.inspection_status,'note',coalesce(a.inspection_note,'')) end,
      'exams',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'examType',coalesce(e.exam_type,''),'examTitle',coalesce(e.exam_title,''),'score',e.score,'maxScore',e.max_score,'percent',case when e.score is null then null else round(e.score*100.0/e.max_score,1) end,'evaluation',coalesce(e.evaluation,''),'feedback','')) from public.teacher_special_lesson_exam_results e where e.session_id=l.id and e.student_id=a.student_id),'[]'::jsonb)
    ) item,l.lesson_date,l.starts_at::text sort_time
 from public.teacher_special_lessons l join public.teacher_special_lesson_students a on a.session_id=l.id and a.student_id=any(p_student_ids)
 join public.profiles p on p.id=l.teacher_profile_id left join public.academy_subjects s on s.id=l.subject_id
 where l.status='completed' and a.attendance_status is not null and l.lesson_date between p_from and p_to
), ranked as (
 select combined.*,row_number() over(partition by combined.student_id order by lesson_date desc,sort_time desc) rn
 from (select student_id,item,lesson_date,sort_time from regular_rows where rn<=500 union all select * from special_rows) combined
), all_rows as (
 select student_id,item,lesson_date,item->>'startsAt' starts_at from ranked where rn<=500
 union all
 select r.student_id,jsonb_build_object(
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
    ) item,r.correction_date,r.start_time::text
 from public.correction_reports r join public.correction_assignments ca on ca.id=r.assignment_id
 where r.student_id=any(p_student_ids) and r.correction_date between p_from and p_to and r.published
)
select all_rows.student_id,jsonb_agg(item order by lesson_date,starts_at) from all_rows group by all_rows.student_id;
$function$;
