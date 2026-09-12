-- Use the same field-level conflict checks as regular class records.
create or replace function public.staff_special_edit_snapshot(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare b jsonb; payload jsonb;
begin
 b:=public.staff_special_lesson_board(p_session_id);
 if b is null then raise exception '수업을 찾을 수 없습니다.'; end if;
 select jsonb_build_object('notice',b->>'notice','rows',coalesce(jsonb_agg(r||jsonb_build_object('studentId',r->>'id')),'[]')) into payload from jsonb_array_elements(b->'students') r;
 return jsonb_build_object('board',b,'values',public.class_edit_values(payload),'state',b->>'state');
end $$;

create or replace function public.staff_patch_special_record(p_session_id uuid,p_changes jsonb,p_expected_state text,p_mode text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare snap jsonb; merged jsonb; payload jsonb; r record; c jsonb;
begin
 if auth.uid() is null or not public.is_staff() then raise exception '교직원만 저장할 수 있습니다.'; end if;
 perform 1 from public.teacher_special_lessons where id=p_session_id and (teacher_profile_id=auth.uid() or public.current_user_role()='admin') for update;
 if not found then raise exception '저장할 수 없는 수업입니다.'; end if;
 if p_mode is null or p_mode not in ('draft','completed','attendance') then raise exception '저장 방식을 확인해 주세요.'; end if;
 -- Lock student records too, so attendance cannot change during completion validation.
 perform 1 from public.teacher_special_lesson_students where session_id=p_session_id order by student_id for update;
 snap:=public.staff_special_edit_snapshot(p_session_id);
 if (snap->>'state') is distinct from p_expected_state then raise exception '다른 창에서 완료 상태가 변경됐습니다. 최신 내용을 비교해 주세요.'; end if;
 for c in select value from jsonb_array_elements(p_changes) loop
  if p_mode='attendance' and (c->'path'->>2 is null or c->'path'->>2 not in ('status','lateMinutes','absenceReason')) then raise exception '출결 항목만 저장할 수 있습니다.'; end if;
  if p_mode<>'attendance' and (c->'path'->>2 in ('status','lateMinutes','absenceReason','note') or c->'path'->>0='lessonContent') then raise exception '수업 기록 항목만 저장할 수 있습니다.'; end if;
 end loop;
 merged:=public.class_merge_edit_changes(snap->'values',p_changes);
 if p_mode='attendance' then
  for r in select key,value from jsonb_each(merged->'students') where key in(select distinct value->'path'->>1 from jsonb_array_elements(p_changes)) loop
   perform public.staff_save_special_lesson_attendance(p_session_id,r.key::uuid,r.value->>'status',(r.value->>'lateMinutes')::integer,nullif(r.value->>'absenceReason',''));
  end loop;
 else
  select coalesce(jsonb_agg(jsonb_build_object('studentId',key,'lessonContent',value->>'lessonContent','assignedHomework',value->>'assignedHomework','inspectionStatus',value->>'inspectionStatus','inspectionNote',value->>'inspectionNote','exam',jsonb_build_object('examType',value->>'exam_examType','examTitle',value->>'exam_examTitle','score',nullif(value->>'exam_score','')::numeric,'maxScore',coalesce(nullif(value->>'exam_maxScore','')::numeric,100),'evaluation',value->>'exam_evaluation'))),'[]') into payload from jsonb_each(merged->'students');
  if exists(select 1 from jsonb_array_elements(payload) row where (nullif(row->'exam'->>'score','') is not null or nullif(trim(row->'exam'->>'examTitle'),'') is not null or nullif(trim(row->'exam'->>'evaluation'),'') is not null) and nullif(trim(row->'exam'->>'examType'),'') is null) then raise exception '시험 종류를 선택해 주세요.'; end if;
  perform public.staff_save_special_lesson_learning(p_session_id,merged->>'notice',payload);
  perform public.staff_set_special_lesson_state(p_session_id,p_mode);
 end if;
 return public.staff_special_edit_snapshot(p_session_id);
end $$;
revoke all on function public.staff_special_edit_snapshot(uuid),public.staff_patch_special_record(uuid,jsonb,text,text) from public,anon;
grant execute on function public.staff_special_edit_snapshot(uuid),public.staff_patch_special_record(uuid,jsonb,text,text) to authenticated;
notify pgrst,'reload schema';
CREATE OR REPLACE FUNCTION public.specialized_learning_history_range(p_student_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  viewer_role public.user_role;
  safe_limit integer;
  result jsonb;
begin
  viewer_role := public.current_user_role();
  if viewer_role is null or viewer_role not in ('admin','teacher','sub_admin') then
    raise exception '교직원 계정만 학생 수업 기록을 확인할 수 있습니다.';
  end if;
  if p_student_id is null then return '[]'::jsonb; end if;
  safe_limit := greatest(1, least(500, 500));

  select coalesce(jsonb_agg(report_row order by lesson_date desc, starts_at desc), '[]'::jsonb)
  into result
  from (
    select jsonb_build_object(
      'lessonId', l.id,
      'lessonDate', to_char(l.lesson_date, 'YYYY-MM-DD'),
      'startsAt', l.starts_at,
      'classId', c.id,
      'className', c.name,
      'subject', c.subject,
      'room', coalesce(l.room, c.room),
      'teacherName', coalesce(tp.display_name, '담당 선생님'),
      'lessonContent', coalesce(l.lesson_content, ''),
      'homeworkContent', coalesce(nullif(trim(hr.assigned_homework), ''), nullif(trim(l.homework_content), ''), ''),
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
        from public.lesson_exam_results er
        where er.lesson_id = l.id
          and er.student_id = p_student_id
          and (
            er.score is not null
            or nullif(trim(coalesce(er.exam_type, '')), '') is not null
            or nullif(trim(coalesce(er.exam_title, '')), '') is not null
            or nullif(trim(coalesce(er.evaluation, '')), '') is not null
            or nullif(trim(coalesce(er.feedback, '')), '') is not null
          )
      ), '[]'::jsonb)
    ) as report_row, l.lesson_date, l.starts_at
    from public.lessons l
    join public.classes c on c.id = l.class_id
    join public.enrollments e on e.class_id = c.id and e.student_id = p_student_id
    left join public.profiles tp on tp.id = l.teacher_profile_id
    left join public.attendance a on a.lesson_id = l.id and a.student_id = p_student_id
    left join public.lesson_homework_results hr on hr.lesson_id = l.id and hr.student_id = p_student_id
    where e.started_on <= l.lesson_date
      and (e.ended_on is null or e.ended_on >= l.lesson_date)
      and l.lesson_date <= current_date
      and l.lesson_date between p_from and p_to
      and (
        a.id is not null
        or nullif(trim(l.lesson_content), '') is not null
        or nullif(trim(l.homework_content), '') is not null
        or nullif(trim(l.exam_content), '') is not null
        or (
          hr.id is not null and (
            nullif(trim(coalesce(hr.status, '')), '') is not null
            or nullif(trim(coalesce(hr.note, '')), '') is not null
            or nullif(trim(coalesce(hr.assigned_homework, '')), '') is not null
            or nullif(trim(coalesce(hr.inspection_status, '')), '') is not null
            or nullif(trim(coalesce(hr.inspection_note, '')), '') is not null
          )
        )
        or exists (
          select 1 from public.lesson_exam_results er
          where er.lesson_id = l.id
            and er.student_id = p_student_id
            and (
              er.score is not null
              or nullif(trim(coalesce(er.exam_type, '')), '') is not null
              or nullif(trim(coalesce(er.exam_title, '')), '') is not null
              or nullif(trim(coalesce(er.evaluation, '')), '') is not null
              or nullif(trim(coalesce(er.feedback, '')), '') is not null
            )
        )
      )
    order by l.lesson_date desc, l.starts_at desc
    limit safe_limit
  ) reports;
  return result;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.specialized_completed_history_range(p_student_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb; safe_limit integer;
begin
  if not public.is_staff() and not public.can_send_alimtalk() then raise exception '교직원만 학생 수업 기록을 확인할 수 있습니다.'; end if;
  if not exists(select 1 from public.students where id=p_student_id) then raise exception '학생을 찾을 수 없습니다.'; end if;
  safe_limit:=greatest(1,least(500,500));
  select coalesce(jsonb_agg(item order by lesson_date desc,starts_at desc),'[]'::jsonb) into result
  from (select item,lesson_date,starts_at from (
    select jsonb_set(jsonb_set(entry.item,'{lessonContent}',to_jsonb(coalesce(nullif(trim(hr.lesson_content),''),entry.item->>'lessonContent',''))),'{source}','"regular"'::jsonb) item,
      l.lesson_date,l.starts_at::text starts_at
    from jsonb_array_elements(coalesce(public.specialized_learning_history_range(p_student_id,p_from,p_to),'[]'::jsonb)) entry(item)
    join public.lessons l on l.id=(entry.item->>'lessonId')::uuid
    left join public.lesson_homework_results hr on hr.lesson_id=l.id and hr.student_id=p_student_id
    where l.status='completed' and jsonb_typeof(entry.item->'attendance')='object'
    union all
    select jsonb_build_object(
      'lessonId',l.id,'lessonDate',to_char(l.lesson_date,'YYYY-MM-DD'),'startsAt',to_char(l.lesson_date,'YYYY-MM-DD')||'T'||l.starts_at::text||'+09:00',
      'classId',l.id,'className',case when l.kind='makeup' then '개별 보강' else '추가수업' end,
      'subject',coalesce(s.name,'과목 미지정'),'source',l.kind,'room',l.room,'teacherName',coalesce(p.display_name,'담당 선생님'),
      'lessonContent',coalesce(a.lesson_content,''),'homeworkContent',coalesce(a.assigned_homework,''),'examContent','',
      'attendance',case when a.attendance_status is null then null else jsonb_build_object('status',a.attendance_status,'lateMinutes',a.late_minutes,'absenceReason',coalesce(a.absence_reason,''),'note','') end,
      'homeworkResult',case when a.inspection_status is null then null else jsonb_build_object('status',a.inspection_status,'note',coalesce(a.inspection_note,'')) end,
      'exams',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'examType',coalesce(e.exam_type,''),'examTitle',coalesce(e.exam_title,''),'score',e.score,'maxScore',e.max_score,'percent',case when e.score is null then null else round(e.score*100.0/e.max_score,1) end,'evaluation',coalesce(e.evaluation,''),'feedback','')) from public.teacher_special_lesson_exam_results e where e.session_id=l.id and e.student_id=p_student_id),'[]'::jsonb)
    ) item,l.lesson_date,l.starts_at::text starts_at
    from public.teacher_special_lessons l
    join public.teacher_special_lesson_students a on a.session_id=l.id and a.student_id=p_student_id
    join public.profiles p on p.id=l.teacher_profile_id
    left join public.academy_subjects s on s.id=l.subject_id
    where l.status='completed' and a.attendance_status is not null and l.lesson_date between p_from and p_to
  ) combined order by lesson_date desc,starts_at desc limit safe_limit) limited;
  return result;
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_learning_report_source(p_student_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare base_rows jsonb; result jsonb;
begin
  if p_from is null or p_to is null or p_to<p_from or p_to-p_from>31 then raise exception '조회 기간을 확인해 주세요.'; end if;
  if not (public.can_staff_report_student(p_student_id) or public.can_send_alimtalk()) then raise exception '담당 학생의 리포트만 만들 수 있습니다.'; end if;
  base_rows:=public.specialized_completed_history_range(p_student_id,p_from,p_to);
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
      and (public.can_send_alimtalk() or ca.teacher_profile_id=auth.uid())
  ) rows;
  return result;
end $function$
;
revoke all on function public.specialized_learning_history_range(uuid,date,date),public.specialized_completed_history_range(uuid,date,date) from public,anon,authenticated;
