-- Per-student classification; null retains the existing session classification.
alter table public.teacher_special_lesson_students add column lesson_kind text check(lesson_kind in ('makeup','additional'));
alter table public.teacher_special_lesson_students add column makeup_source text check(makeup_source in ('regular','correction','special'));
alter table public.teacher_special_lesson_students add column makeup_source_id uuid;
alter table public.teacher_special_lesson_students add constraint special_makeup_source_pair check((makeup_source is null)=(makeup_source_id is null));
create unique index special_makeup_source_once on public.teacher_special_lesson_students(makeup_source,makeup_source_id,student_id) where makeup_source_id is not null;
create or replace function public.internal_special_student_kind(p_session_id uuid,p_student_id uuid)
returns text language sql stable security invoker set search_path=public as $$
 select coalesce(a.lesson_kind,l.kind) from public.teacher_special_lessons l
 left join public.teacher_special_lesson_students a on a.session_id=l.id and a.student_id=p_student_id where l.id=p_session_id
$$;
revoke all on function public.internal_special_student_kind(uuid,uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.family_summary_snapshot(p_student_id uuid, p_start_date date, p_end_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
        'classId',l.id,'className',case when public.internal_special_student_kind(l.id,selected_id)='makeup' then '개별 보강' else '추가수업' end,
        'subject',case when public.internal_special_student_kind(l.id,selected_id)='makeup' then '보강' else '추가수업' end,
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

CREATE OR REPLACE FUNCTION public.family_completed_learning_reports(p_student_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare viewer_role public.user_role; selected_id uuid; safe_limit integer; result jsonb;
begin
  viewer_role:=public.current_user_role();
  if viewer_role is null or viewer_role not in ('student','guardian') then
    raise exception '학생 또는 학부모 계정만 학습리포트를 확인할 수 있습니다.';
  end if;
  if viewer_role='student' then
    select s.id into selected_id from public.students s where s.profile_id=auth.uid();
    if p_student_id is not null and p_student_id<>selected_id then raise exception '본인 학습리포트만 확인할 수 있습니다.'; end if;
  else
    select s.id into selected_id from public.guardians g
    join public.student_guardians sg on sg.guardian_id=g.id
    join public.students s on s.id=sg.student_id
    where g.profile_id=auth.uid() and (p_student_id is null or s.id=p_student_id)
    order by sg.is_primary desc,s.name limit 1;
    if selected_id is null then raise exception '연결된 자녀의 학습리포트만 확인할 수 있습니다.'; end if;
  end if;
  safe_limit:=greatest(1,least(coalesce(p_limit,10),30));
  select coalesce(jsonb_agg(item order by lesson_date desc,starts_at desc),'[]'::jsonb) into result
  from (
    select item,lesson_date,starts_at from (
      select jsonb_set(entry.item,'{lessonContent}',to_jsonb(coalesce(nullif(trim(hr.lesson_content),''),entry.item->>'lessonContent',''))) item,
        l.lesson_date,l.starts_at::text starts_at
      from jsonb_array_elements(coalesce(public.family_learning_reports(selected_id,30),'[]'::jsonb)) entry(item)
      join public.lessons l on l.id=(entry.item->>'lessonId')::uuid
      left join public.lesson_homework_results hr on hr.lesson_id=l.id and hr.student_id=selected_id
      where l.status='completed' and jsonb_typeof(entry.item->'attendance')='object'
      union all
      select jsonb_build_object(
        'lessonId',l.id,'lessonDate',to_char(l.lesson_date,'YYYY-MM-DD'),
        'startsAt',to_char(l.lesson_date,'YYYY-MM-DD')||'T'||l.starts_at::text||'+09:00',
        'classId',l.id,'className',case when public.internal_special_student_kind(l.id,selected_id)='makeup' then '개별 보강' else '추가수업' end,
        'subject',case when public.internal_special_student_kind(l.id,selected_id)='makeup' then '보강' else '추가수업' end,
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
      where l.status='completed' and l.lesson_date<=current_date
    ) combined order by lesson_date desc,starts_at desc limit safe_limit
  ) limited;
  return result;
end $function$;

CREATE OR REPLACE FUNCTION public.staff_student_completed_learning_history(p_student_id uuid, p_limit integer DEFAULT 300)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb; safe_limit integer;
begin
  if not public.is_staff() and not public.can_send_alimtalk() then raise exception '교직원만 학생 수업 기록을 확인할 수 있습니다.'; end if;
  if not exists(select 1 from public.students where id=p_student_id) then raise exception '학생을 찾을 수 없습니다.'; end if;
  safe_limit:=greatest(1,least(coalesce(p_limit,300),500));
  select coalesce(jsonb_agg(item order by lesson_date desc,starts_at desc),'[]'::jsonb) into result
  from (select item,lesson_date,starts_at from (
    select jsonb_set(jsonb_set(entry.item,'{lessonContent}',to_jsonb(coalesce(nullif(trim(hr.lesson_content),''),entry.item->>'lessonContent',''))),'{source}','"regular"'::jsonb) item,
      l.lesson_date,l.starts_at::text starts_at
    from jsonb_array_elements(coalesce(public.staff_student_learning_history(p_student_id,safe_limit),'[]'::jsonb)) entry(item)
    join public.lessons l on l.id=(entry.item->>'lessonId')::uuid
    left join public.lesson_homework_results hr on hr.lesson_id=l.id and hr.student_id=p_student_id
    where l.status='completed' and jsonb_typeof(entry.item->'attendance')='object'
    union all
    select jsonb_build_object(
      'lessonId',l.id,'lessonDate',to_char(l.lesson_date,'YYYY-MM-DD'),'startsAt',to_char(l.lesson_date,'YYYY-MM-DD')||'T'||l.starts_at::text||'+09:00',
      'classId',l.id,'className',case when public.internal_special_student_kind(l.id,p_student_id)='makeup' then '개별 보강' else '추가수업' end,
      'subject',coalesce(s.name,'과목 미지정'),'source',public.internal_special_student_kind(l.id,p_student_id),'room',l.room,'teacherName',coalesce(p.display_name,'담당 선생님'),
      'lessonContent',coalesce(a.lesson_content,''),'homeworkContent',coalesce(a.assigned_homework,''),'examContent','',
      'attendance',case when a.attendance_status is null then null else jsonb_build_object('status',a.attendance_status,'lateMinutes',a.late_minutes,'absenceReason',coalesce(a.absence_reason,''),'note','') end,
      'homeworkResult',case when a.inspection_status is null then null else jsonb_build_object('status',a.inspection_status,'note',coalesce(a.inspection_note,'')) end,
      'exams',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'examType',coalesce(e.exam_type,''),'examTitle',coalesce(e.exam_title,''),'score',e.score,'maxScore',e.max_score,'percent',case when e.score is null then null else round(e.score*100.0/e.max_score,1) end,'evaluation',coalesce(e.evaluation,''),'feedback','')) from public.teacher_special_lesson_exam_results e where e.session_id=l.id and e.student_id=p_student_id),'[]'::jsonb)
    ) item,l.lesson_date,l.starts_at::text starts_at
    from public.teacher_special_lessons l
    join public.teacher_special_lesson_students a on a.session_id=l.id and a.student_id=p_student_id
    join public.profiles p on p.id=l.teacher_profile_id
    left join public.academy_subjects s on s.id=l.subject_id
    where l.status='completed' and a.attendance_status is not null
  ) combined order by lesson_date desc,starts_at desc limit safe_limit) limited;
  return result;
end $function$;

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
      'classId',l.id,'className',case when public.internal_special_student_kind(l.id,p_student_id)='makeup' then '개별 보강' else '추가수업' end,
      'subject',coalesce(s.name,'과목 미지정'),'source',public.internal_special_student_kind(l.id,p_student_id),'room',l.room,'teacherName',coalesce(p.display_name,'담당 선생님'),
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
end $function$;

CREATE OR REPLACE FUNCTION public.family_learning_calendar_schedule(p_student_id uuid DEFAULT NULL::uuid, p_month date DEFAULT (date_trunc('month'::text, timezone('Asia/Seoul'::text, now())))::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  base jsonb;
  sid uuid;
  month_start date := date_trunc('month', p_month)::date;
  month_end date := (date_trunc('month', p_month) + interval '1 month - 1 day')::date;
  result jsonb;
begin
  base := public.family_live_dashboard(p_student_id);
  sid := nullif(base->'selectedStudent'->>'id', '')::uuid;
  if sid is null then return '[]'::jsonb; end if;

  with recursive month_days as (
    select month_start as class_date
    union all
    select class_date + 1 from month_days where class_date < month_end
  ), regular_base as (
    select
      'regular:' || cs.id::text || ':' || d.class_date::text as id,
      d.class_date, cs.start_time, cs.end_time, 'regular'::text as kind,
      '정규수업'::text as label, c.name as title, c.subject,
      coalesce(c.room, '') as room, 'scheduled'::text as state, null::text as attendance_status
    from month_days d
    join public.class_schedules cs on cs.weekday = extract(isodow from d.class_date)::smallint
      and (cs.valid_from is null or cs.valid_from <= d.class_date)
      and (cs.valid_until is null or cs.valid_until >= d.class_date)
    join public.classes c on c.id = cs.class_id and c.active
    join public.enrollments e on e.class_id = c.id and e.student_id = sid
      and e.status = 'active' and e.started_on <= d.class_date
      and (e.ended_on is null or e.ended_on >= d.class_date)
    where (not exists(select 1 from public.student_schedule_assignments ssa where ssa.student_id = sid)
      or exists(select 1 from public.student_schedule_assignments ssa where ssa.student_id = sid and ssa.class_schedule_id = cs.id))
      and not exists (
        select 1 from public.schedule_exceptions x
        where x.class_id = c.id and x.original_date = d.class_date
          and x.kind in ('cancelled', 'changed', 'makeup')
      )
  ), regular_replacements as (
    select
      'regular-change:' || x.id::text as id, x.replacement_date as class_date,
      coalesce(x.start_time, cs.start_time) as start_time, coalesce(x.end_time, cs.end_time) as end_time,
      case when x.kind = 'makeup' then 'makeup' else 'regular' end as kind,
      case when x.kind = 'makeup' then '보강' else '변경수업' end as label,
      c.name as title, c.subject, coalesce(x.room, c.room, '') as room,
      'scheduled'::text as state, null::text as attendance_status
    from public.schedule_exceptions x
    join public.classes c on c.id = x.class_id and c.active
    join public.enrollments e on e.class_id = c.id and e.student_id = sid and e.status = 'active'
    left join lateral (
      select s.start_time, s.end_time from public.class_schedules s
      where s.class_id = c.id order by s.start_time limit 1
    ) cs on true
    where x.replacement_date between month_start and month_end
      and x.kind in ('changed', 'makeup')
      and e.started_on <= x.replacement_date
      and (e.ended_on is null or e.ended_on >= x.replacement_date)
  ), correction_base as (
    select
      'correction:' || a.id::text || ':' || d.class_date::text as id,
      d.class_date, a.start_time, a.end_time, 'correction'::text as kind,
      '첨삭'::text as label, coalesce(a.subject, '첨삭') || ' 첨삭수업' as title,
      coalesce(a.subject, '첨삭') as subject, ''::text as room,
      'scheduled'::text as state, null::text as attendance_status
    from month_days d
    join public.correction_assignments a on a.student_id = sid and a.active
      and a.weekday = extract(isodow from d.class_date)::smallint
      and a.valid_from <= d.class_date and (a.valid_until is null or a.valid_until >= d.class_date)
    where not exists (
      select 1 from public.correction_schedule_exceptions x
      where x.assignment_id = a.id and x.original_date = d.class_date and x.kind in ('move', 'cancel')
    )
  ), correction_changes as (
    select
      'correction-change:' || x.id::text as id, x.target_date as class_date,
      coalesce(x.target_start_time, a.start_time) as start_time,
      coalesce(x.target_end_time, a.end_time) as end_time,
      'correction'::text as kind,
      case when x.kind = 'extra' then '추가 첨삭' else '변경 첨삭' end as label,
      coalesce(a.subject, '첨삭') || ' 첨삭수업' as title,
      coalesce(a.subject, '첨삭') as subject, ''::text as room,
      'scheduled'::text as state, null::text as attendance_status
    from public.correction_schedule_exceptions x
    join public.correction_assignments a on a.id = x.assignment_id and a.student_id = sid
    where x.target_date between month_start and month_end and x.kind in ('move', 'extra')
  ), special as (
    select
      'special:' || l.id::text as id, l.lesson_date as class_date,
      l.starts_at as start_time, l.ends_at as end_time,
      case when public.internal_special_student_kind(l.id,sid) = 'makeup' then 'makeup' else 'extra' end as kind,
      case when public.internal_special_student_kind(l.id,sid) = 'makeup' then '보강' else '추가수업' end as label,
      coalesce(s.name, case when public.internal_special_student_kind(l.id,sid) = 'makeup' then '보강수업' else '추가수업' end) as title,
      coalesce(s.name, '개별수업') as subject, coalesce(l.room, '') as room,
      case when coalesce(l.status, 'scheduled') = 'cancelled' then 'cancelled' else 'scheduled' end as state,
      ss.attendance_status
    from public.teacher_special_lessons l
    join public.teacher_special_lesson_students ss on ss.session_id = l.id and ss.student_id = sid
    left join public.academy_subjects s on s.id = l.subject_id
    where l.lesson_date between month_start and month_end
  ), rows as (
    select * from regular_base
    union all select * from regular_replacements
    union all select * from correction_base
    union all select * from correction_changes
    union all select * from special
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'date', to_char(class_date, 'YYYY-MM-DD'),
    'startTime', to_char(start_time, 'HH24:MI'), 'endTime', to_char(end_time, 'HH24:MI'),
    'kind', kind, 'label', label, 'title', title, 'subject', subject,
    'room', room, 'state', state, 'attendanceStatus', attendance_status
  ) order by class_date, start_time, id), '[]'::jsonb) into result from rows;
  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.family_exam_progress(p_student_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role public.user_role; v_student_id uuid; v_result jsonb;
begin
  v_role:=public.current_user_role();
  if v_role not in ('student','guardian') then raise exception '학생 또는 학부모 계정만 시험 결과를 확인할 수 있습니다.'; end if;
  if v_role='student' then
    select s.id into v_student_id from public.students s where s.profile_id=auth.uid();
    if p_student_id is not null and p_student_id<>v_student_id then raise exception '본인의 시험 결과만 확인할 수 있습니다.'; end if;
  else
    select s.id into v_student_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id
    where g.profile_id=auth.uid() and (p_student_id is null or s.id=p_student_id) order by sg.is_primary desc,s.name limit 1;
    if p_student_id is not null and v_student_id is null then raise exception '연결된 자녀의 시험 결과만 확인할 수 있습니다.'; end if;
  end if;
  select coalesce(jsonb_agg(row_data order by lesson_date desc,created_at desc),'[]'::jsonb) into v_result from (
    select lesson_date,created_at,jsonb_build_object('id',id,'lessonDate',lesson_date,'className',class_name,'subject',subject_name,'mainSubject',main_subject,'examType',exam_type,'examTitle',exam_title,'itemType',item_type,'score',score,'maxScore',max_score,'percent',percent,'evaluation',evaluation,'feedback',feedback,'teacherName',teacher_name) row_data
    from (
      select r.id,r.created_at,l.lesson_date,c.name class_name,coalesce(subject.name,c.subject) subject_name,coalesce(subject.main_subject,c.subject) main_subject,
        coalesce(r.exam_type,'') exam_type,coalesce(r.exam_title,l.exam_content,'') exam_title,'regular'::text item_type,r.score,coalesce(nullif(r.max_score,0),100) max_score,
        case when r.score is null then null else round(r.score/coalesce(nullif(r.max_score,0),100)*100,1) end percent,coalesce(r.evaluation,'') evaluation,coalesce(r.feedback,'') feedback,coalesce(p.display_name,'담당 선생님') teacher_name
      from public.lesson_exam_results r join public.lessons l on l.id=r.lesson_id join public.classes c on c.id=l.class_id
      left join public.academy_subjects subject on subject.id=c.subject_id left join public.profiles p on p.id=coalesce(r.created_by,l.teacher_profile_id)
      where r.student_id=v_student_id and r.score is not null
      union all
      select r.id,r.updated_at,l.lesson_date,case when public.internal_special_student_kind(l.id,v_student_id)='makeup' then '개별 보강' else '추가수업' end,
        coalesce(subject.name,case when public.internal_special_student_kind(l.id,v_student_id)='makeup' then '보강' else '추가수업' end),coalesce(subject.main_subject,subject.name,''),coalesce(r.exam_type,''),coalesce(r.exam_title,''),
        case when public.internal_special_student_kind(l.id,v_student_id)='makeup' then 'makeup' else 'extra' end,r.score,coalesce(nullif(r.max_score,0),100),
        case when r.score is null then null else round(r.score/coalesce(nullif(r.max_score,0),100)*100,1) end,coalesce(r.evaluation,''),coalesce(r.evaluation,''),coalesce(p.display_name,'담당 선생님')
      from public.teacher_special_lesson_exam_results r join public.teacher_special_lessons l on l.id=r.session_id
      join public.teacher_special_lesson_students a on a.session_id=l.id and a.student_id=v_student_id
      left join public.academy_subjects subject on subject.id=l.subject_id left join public.profiles p on p.id=l.teacher_profile_id
      where r.student_id=v_student_id and l.status='completed' and r.score is not null
    ) all_exams order by lesson_date desc,created_at desc limit 120
  ) exam_rows;
  return v_result;
end $function$;

CREATE OR REPLACE FUNCTION public.family_today_lessons(p_student_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sid uuid; today date := (now() at time zone 'Asia/Seoul')::date; result jsonb;
begin
  sid:=public.internal_family_student_id(p_student_id);
  if sid is null then return '[]'::jsonb; end if;
  with rows as (
    select 'regular:'||l.id::text id,'regular' kind,'정규수업' label,coalesce(c.subject,c.name) subject,to_char(l.starts_at at time zone 'Asia/Seoul','HH24:MI') start_time,to_char(l.ends_at at time zone 'Asia/Seoul','HH24:MI') end_time,coalesce(p.display_name,'') teacher_name,coalesce(l.room,c.room,'') room,a.status::text attendance_status
    from public.lessons l join public.classes c on c.id=l.class_id left join public.profiles p on p.id=l.teacher_profile_id left join public.attendance a on a.lesson_id=l.id and a.student_id=sid where l.lesson_date=today and (a.id is not null or (l.status<>'cancelled' and (
      exists(select 1 from public.schedule_exceptions x where x.class_id=c.id
        and x.kind in ('changed','makeup') and x.replacement_date=today
        and (x.start_time is null or x.start_time=(l.starts_at at time zone 'Asia/Seoul')::time)
        and public.student_attends_class_on(sid,c.id,x.original_date))
      or (
        public.student_attends_class_on(sid,c.id,today)
        and not exists(select 1 from public.schedule_exceptions x
          where x.class_id=c.id and x.original_date=today and x.kind in ('cancelled','changed','makeup'))
      )
    )))
    union all
    select 'special:'||l.id::text,'special',case public.internal_special_student_kind(l.id,sid) when 'makeup' then '보강' when 'extra' then '추가수업' when 'additional' then '추가수업' else '개별수업' end,coalesce(s.name,'과목 미지정'),to_char(l.starts_at,'HH24:MI'),to_char(l.ends_at,'HH24:MI'),coalesce(p.display_name,''),coalesce(l.room,''),ss.attendance_status
    from public.teacher_special_lessons l join public.teacher_special_lesson_students ss on ss.session_id=l.id and ss.student_id=sid left join public.academy_subjects s on s.id=l.subject_id left join public.profiles p on p.id=l.teacher_profile_id where l.lesson_date=today and coalesce(l.status,'scheduled')<>'cancelled'
    union all
    select 'correction:'||ca.id::text,'correction','첨삭',coalesce(ca.subject,'과목 미지정'),to_char(ca.start_time,'HH24:MI'),to_char(ca.end_time,'HH24:MI'),coalesce(p.display_name,''),'',cr.attendance_status
    from public.correction_assignments ca left join public.profiles p on p.id=coalesce(ca.tutor_profile_id,ca.teacher_profile_id) left join public.correction_reports cr on cr.assignment_id=ca.id and cr.student_id=sid and cr.correction_date=today and cr.start_time=ca.start_time
    where ca.student_id=sid and ca.active and ca.valid_from<=today and (ca.valid_until is null or ca.valid_until>=today) and ca.weekday=extract(isodow from today)::int and not exists(select 1 from public.correction_schedule_exceptions x where x.assignment_id=ca.id and x.original_date=today and x.kind in ('cancel','move'))
    union all
    select 'correction-move:'||x.id::text,'correction','첨삭',coalesce(ca.subject,'과목 미지정'),to_char(coalesce(x.target_start_time,ca.start_time),'HH24:MI'),to_char(coalesce(x.target_end_time,ca.end_time),'HH24:MI'),coalesce(p.display_name,''),'',cr.attendance_status
    from public.correction_schedule_exceptions x join public.correction_assignments ca on ca.id=x.assignment_id and ca.student_id=sid left join public.profiles p on p.id=coalesce(ca.tutor_profile_id,ca.teacher_profile_id) left join public.correction_reports cr on cr.assignment_id=ca.id and cr.student_id=sid and cr.correction_date=today and cr.start_time=coalesce(x.target_start_time,ca.start_time) where x.target_date=today and x.kind in ('move','extra')
  )
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'kind',kind,'label',label,'subject',subject,'startTime',start_time,'endTime',end_time,'teacherName',teacher_name,'room',room,'attendanceStatus',attendance_status) order by start_time,id),'[]'::jsonb) into result from rows;
  return result;
end $function$;

CREATE OR REPLACE FUNCTION public.staff_student_special_lesson_insights(p_student_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_staff() then raise exception '교직원만 학생 통합 기록을 확인할 수 있습니다.'; end if;
  if not exists(select 1 from public.students where id=p_student_id) then raise exception '학생을 찾을 수 없습니다.'; end if;
  return jsonb_build_object(
    'attendance',jsonb_build_object(
      'attendanceTotal',(select count(*) from public.teacher_special_lesson_students a join public.teacher_special_lessons l on l.id=a.session_id where a.student_id=p_student_id and l.lesson_date>=current_date-30 and a.attendance_status is not null),
      'present',(select count(*) from public.teacher_special_lesson_students a join public.teacher_special_lessons l on l.id=a.session_id where a.student_id=p_student_id and l.lesson_date>=current_date-30 and a.attendance_status='present'),
      'late',(select count(*) from public.teacher_special_lesson_students a join public.teacher_special_lessons l on l.id=a.session_id where a.student_id=p_student_id and l.lesson_date>=current_date-30 and a.attendance_status='late'),
      'absent',(select count(*) from public.teacher_special_lesson_students a join public.teacher_special_lessons l on l.id=a.session_id where a.student_id=p_student_id and l.lesson_date>=current_date-30 and a.attendance_status='absent')
    ),
    'upcomingMakeups',(select count(*) from public.teacher_special_lesson_students a join public.teacher_special_lessons l on l.id=a.session_id where a.student_id=p_student_id and public.internal_special_student_kind(l.id,p_student_id)='makeup' and l.lesson_date>=current_date),
    'exams',coalesce((select jsonb_agg(to_jsonb(q) order by q."lessonDate",q.id) from (
      select e.id,l.lesson_date as "lessonDate",case when public.internal_special_student_kind(l.id,p_student_id)='makeup' then '개별 보강' else '추가수업' end as "className",
        coalesce(subject.name,subject.main_subject,'과목 미지정') as subject,
        coalesce(e.exam_type,'') as "examType",coalesce(e.exam_title,'') as "examTitle",
        e.score,coalesce(e.max_score,100) as "maxScore",
        case when e.score is null then null else round(e.score*100.0/coalesce(nullif(e.max_score,0),100),1) end as percent,
        coalesce(e.evaluation,'') as evaluation
      from public.teacher_special_lesson_exam_results e
      join public.teacher_special_lessons l on l.id=e.session_id
      left join public.academy_subjects subject on subject.id=l.subject_id
      where e.student_id=p_student_id and l.status='completed' and e.score is not null
      order by l.lesson_date desc,e.created_at desc limit 100
    ) q),'[]'::jsonb)
  );
end $function$;

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
      'classId',l.id,'className',case when public.internal_special_student_kind(l.id,a.student_id)='makeup' then '개별 보강' else '추가수업' end,
      'subject',coalesce(s.name,'과목 미지정'),'source',case when public.internal_special_student_kind(l.id,a.student_id)='additional' then 'extra' else public.internal_special_student_kind(l.id,a.student_id) end,'room',l.room,'teacherName',coalesce(p.display_name,'담당 선생님'),
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

CREATE OR REPLACE FUNCTION public.staff_alimtalk_ready_students(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
  if not public.can_send_alimtalk() then raise exception '관리자만 알림톡 발송 대상을 확인할 수 있습니다.'; end if;
  if p_from is null or p_to is null or p_to<p_from or p_to-p_from>6 then raise exception '발송 기간을 확인해 주세요.'; end if;

  with days as (
    select generate_series(p_from,p_to,'1 day'::interval)::date occurrence_date
  ),
  regular_fixed as (
    select distinct e.student_id,'regular:'||cs.class_id||':'||d.occurrence_date||':'||cs.start_time expected_key,
      '정규수업' kind,c.name title,d.occurrence_date,cs.start_time,
      exists(select 1 from public.lessons l join public.attendance at on at.lesson_id=l.id and at.student_id=e.student_id where l.class_id=cs.class_id and l.lesson_date=d.occurrence_date and l.status='completed') completed
    from days d join public.class_schedules cs on cs.weekday=extract(isodow from d.occurrence_date)::smallint
      and (cs.valid_from is null or cs.valid_from<=d.occurrence_date) and (cs.valid_until is null or cs.valid_until>=d.occurrence_date)
    join public.classes c on c.id=cs.class_id and c.active
    join public.enrollments e on e.class_id=c.id and e.status='active' and e.started_on<=d.occurrence_date and (e.ended_on is null or e.ended_on>=d.occurrence_date)
    join public.students s on s.id=e.student_id and s.status in ('active','재원')
    where public.student_attends_class_on(e.student_id, cs.class_id, d.occurrence_date)
      and not exists(select 1 from public.schedule_exceptions x where x.class_id=cs.class_id and x.original_date=d.occurrence_date and x.kind in ('cancelled','changed','makeup'))
  ),
  regular_replacements as (
    select distinct e.student_id,'regular:'||x.class_id||':'||x.replacement_date||':'||coalesce(x.start_time,cs.start_time) expected_key,
      case when x.kind='makeup' then '보강수업' else '변경수업' end,c.name,x.replacement_date,coalesce(x.start_time,cs.start_time),
      exists(select 1 from public.lessons l join public.attendance at on at.lesson_id=l.id and at.student_id=e.student_id where l.class_id=x.class_id and l.lesson_date=x.replacement_date and l.status='completed')
    from public.schedule_exceptions x join public.class_schedules cs on cs.class_id=x.class_id and cs.weekday=extract(isodow from x.original_date)::smallint
    join public.classes c on c.id=x.class_id and c.active join public.enrollments e on e.class_id=c.id and e.status='active'
      and e.started_on<=x.replacement_date and (e.ended_on is null or e.ended_on>=x.replacement_date)
    join public.students s on s.id=e.student_id and s.status in ('active','재원')
    where x.kind in ('changed','makeup') and x.replacement_date between p_from and p_to
  ),
  class_makeups as (
    select distinct m.student_id,'class-makeup:'||m.class_id||':'||m.attendance_date expected_key,'보강수업',c.name,m.attendance_date,cs.start_time,
      exists(select 1 from public.lessons l join public.attendance at on at.lesson_id=l.id and at.student_id=m.student_id where l.class_id=m.class_id and l.lesson_date=m.attendance_date and l.status='completed')
    from public.class_makeup_attendees m join public.classes c on c.id=m.class_id
    left join public.class_schedules cs on cs.class_id=m.class_id and cs.weekday=extract(isodow from m.attendance_date)::smallint
    join public.students s on s.id=m.student_id and s.status in ('active','재원') where m.attendance_date between p_from and p_to
  ),
  special_lessons as (
    select a.student_id,'special:'||l.id expected_key,case when public.internal_special_student_kind(l.id,a.student_id)='makeup' then '개별 보강' else '추가수업' end,
      coalesce(sub.name,case when public.internal_special_student_kind(l.id,a.student_id)='makeup' then '보강' else '추가수업' end),l.lesson_date,l.starts_at,
      l.status='completed' and a.attendance_status is not null
    from public.teacher_special_lessons l join public.teacher_special_lesson_students a on a.session_id=l.id
    join public.students s on s.id=a.student_id and s.status in ('active','재원') left join public.academy_subjects sub on sub.id=l.subject_id
    where l.lesson_date between p_from and p_to
  ),
  correction_fixed as (
    select a.student_id,'correction:'||a.id||':'||d.occurrence_date||':'||a.start_time expected_key,'첨삭수업',a.subject||' 첨삭',d.occurrence_date,a.start_time,
      exists(select 1 from public.correction_reports r where r.assignment_id=a.id and r.student_id=a.student_id and r.correction_date=d.occurrence_date and r.start_time=a.start_time and r.published and r.attendance_status<>'scheduled')
    from days d join public.correction_assignments a on a.active and a.weekday=extract(isodow from d.occurrence_date)::smallint
      and (a.valid_from is null or a.valid_from<=d.occurrence_date) and (a.valid_until is null or a.valid_until>=d.occurrence_date)
    join public.students s on s.id=a.student_id and s.status in ('active','재원')
    where not exists(select 1 from public.correction_schedule_exceptions x where x.assignment_id=a.id and x.original_date=d.occurrence_date and x.kind in ('move','cancel'))
  ),
  correction_changes as (
    select a.student_id,'correction:'||a.id||':'||x.target_date||':'||x.target_start_time expected_key,'첨삭수업',a.subject||case when x.kind='extra' then ' 추가 첨삭' else ' 첨삭' end,x.target_date,x.target_start_time,
      exists(select 1 from public.correction_reports r where r.assignment_id=a.id and r.student_id=a.student_id and r.correction_date=x.target_date and r.start_time=x.target_start_time and r.published and r.attendance_status<>'scheduled')
    from public.correction_schedule_exceptions x join public.correction_assignments a on a.id=x.assignment_id and a.active
    join public.students s on s.id=a.student_id and s.status in ('active','재원') where x.kind in ('move','extra') and x.target_date between p_from and p_to
  ),
  scheduled_expected as (
    select * from regular_fixed union select * from regular_replacements union select * from class_makeups
    union all select * from special_lessons union all select * from correction_fixed union select * from correction_changes
  ),
  expected as (
    select * from scheduled_expected
    union all
    select a.student_id,'recorded-regular:'||l.id::text,'정규수업',c.name,l.lesson_date,
      (l.starts_at at time zone 'Asia/Seoul')::time,true
    from public.attendance a join public.lessons l on l.id=a.lesson_id
    join public.classes c on c.id=l.class_id
    join public.students s on s.id=a.student_id and s.status in ('active','재원')
    where l.status='completed' and l.lesson_date between p_from and p_to
      and not exists(select 1 from scheduled_expected e
        where e.student_id=a.student_id and e.occurrence_date=l.lesson_date
        and (e.expected_key like 'regular:'||l.class_id::text||':'||l.lesson_date::text||':%'
          or e.expected_key='class-makeup:'||l.class_id::text||':'||l.lesson_date::text))
  ),
  completed_expected as (
    select * from expected where completed
  ),
  unresolved_expected as (
    select
      e.student_id,
      min(e.expected_key) expected_key,
      case when count(*)>1 then '교차수업' else min(e.kind) end kind,
      case when count(*)>1 then string_agg(distinct e.title,' / ' order by e.title) else min(e.title) end title,
      e.occurrence_date,
      e.start_time,
      false completed
    from expected e
    where not e.completed
      and not exists (
        select 1 from expected done
        where done.student_id=e.student_id
          and done.occurrence_date=e.occurrence_date
          and done.start_time is not distinct from e.start_time
          and done.completed
      )
    group by e.student_id,e.occurrence_date,e.start_time
  ),
  resolved_expected as (
    select * from completed_expected
    union all
    select * from unresolved_expected
  ),
  readiness as materialized (
    select student_id,count(*)::integer expected_count,count(*) filter(where completed)::integer completed_count,
      coalesce(jsonb_agg(jsonb_build_object('kind',kind,'title',title,'date',occurrence_date,'time',to_char(start_time,'HH24:MI')) order by occurrence_date,start_time,title) filter(where not completed),'[]'::jsonb) missing_items
    from resolved_expected group by student_id
  ),
  report_sources as materialized (
    select * from public.internal_alimtalk_report_sources(array(select student_id from readiness),p_from,p_to)
  ),
  recipients as materialized (
    select distinct on(sg.student_id) sg.student_id,
      jsonb_build_object('guardianName',g.name,'maskedPhone',left(regexp_replace(g.phone,'[^0-9]','','g'),3)||'-****-'||right(regexp_replace(g.phone,'[^0-9]','','g'),4),'available',true) recipient
    from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id
    where sg.student_id in (select student_id from readiness) and length(regexp_replace(coalesce(g.phone,''),'[^0-9]','','g')) between 10 and 11
    order by sg.student_id,sg.is_primary desc,g.created_at
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'studentId',s.id,'studentName',s.name,'school',coalesce(s.school,''),'grade',coalesce(s.grade,''),
    'expectedCount',r.expected_count,'completedCount',r.completed_count,'complete',r.completed_count=r.expected_count,'missingItems',r.missing_items,
    'lessons',coalesce(src.lessons,'[]'::jsonb),'recipient',coalesce(rec.recipient,jsonb_build_object('guardianName','','maskedPhone','','available',false))
  ) order by (r.completed_count=r.expected_count) desc,s.name,s.id),'[]'::jsonb) into result
  from readiness r join public.students s on s.id=r.student_id left join report_sources src on src.student_id=s.id left join recipients rec on rec.student_id=s.id where r.expected_count>0;
  return result;
end $function$;

CREATE OR REPLACE FUNCTION public.staff_record_worklist(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb; uid uuid:=auth.uid(); admin boolean; today date:=(now() at time zone 'Asia/Seoul')::date;
begin
 if uid is null or not exists(select 1 from public.profiles where id=uid and is_active and role in ('admin','sub_admin','teacher','assistant','manager')) then raise exception '교직원만 기록을 확인할 수 있습니다.';end if;
 admin:=public.current_user_role()='admin';
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>6 or p_to>today or p_from<today-30 then raise exception '최근 30일 내 최대 7일을 선택해 주세요.';end if;
  with days as (
    select generate_series(p_from,p_to,'1 day'::interval)::date occurrence_date
  ),
  regular_fixed as (
    select distinct e.student_id,'regular:'||cs.class_id||':'||d.occurrence_date||':'||cs.start_time expected_key,
      '정규수업' kind,c.name title,d.occurrence_date,cs.start_time,
      exists(select 1 from public.lessons l join public.attendance at on at.lesson_id=l.id and at.student_id=e.student_id where l.class_id=cs.class_id and l.lesson_date=d.occurrence_date and l.status='completed' and at.status::text in ('present','late','absent','excused')) completed
    from days d join public.class_schedules cs on cs.weekday=extract(isodow from d.occurrence_date)::smallint
      and (cs.valid_from is null or cs.valid_from<=d.occurrence_date) and (cs.valid_until is null or cs.valid_until>=d.occurrence_date)
    join public.classes c on c.id=cs.class_id and c.active
    join public.enrollments e on e.class_id=c.id and e.status='active' and e.started_on<=d.occurrence_date and (e.ended_on is null or e.ended_on>=d.occurrence_date)
    join public.students s on s.id=e.student_id and s.status in ('active','재원')
    where public.student_attends_class_on(e.student_id, cs.class_id, d.occurrence_date)
      and not exists(select 1 from public.schedule_exceptions x where x.class_id=cs.class_id and x.original_date=d.occurrence_date and x.kind in ('cancelled','changed','makeup'))
  ),
  regular_replacements as (
    select distinct e.student_id,'regular:'||x.class_id||':'||x.replacement_date||':'||coalesce(x.start_time,cs.start_time) expected_key,
      case when x.kind='makeup' then '보강수업' else '변경수업' end,c.name,x.replacement_date,coalesce(x.start_time,cs.start_time),
      exists(select 1 from public.lessons l join public.attendance at on at.lesson_id=l.id and at.student_id=e.student_id where l.class_id=x.class_id and l.lesson_date=x.replacement_date and l.status='completed' and at.status::text in ('present','late','absent','excused'))
    from public.schedule_exceptions x join public.class_schedules cs on cs.class_id=x.class_id and cs.weekday=extract(isodow from x.original_date)::smallint
    join public.classes c on c.id=x.class_id and c.active join public.enrollments e on e.class_id=c.id and e.status='active'
      and e.started_on<=x.replacement_date and (e.ended_on is null or e.ended_on>=x.replacement_date)
    join public.students s on s.id=e.student_id and s.status in ('active','재원')
    where (cs.valid_from is null or cs.valid_from<=x.original_date) and (cs.valid_until is null or cs.valid_until>=x.original_date) and public.student_attends_class_on(e.student_id,x.class_id,x.original_date) and x.kind in ('changed','makeup') and x.replacement_date between p_from and p_to
  ),
  class_makeups as (
    select distinct m.student_id,'class-makeup:'||m.class_id||':'||m.attendance_date expected_key,'보강수업',c.name,m.attendance_date,cs.start_time,
      exists(select 1 from public.lessons l join public.attendance at on at.lesson_id=l.id and at.student_id=m.student_id where l.class_id=m.class_id and l.lesson_date=m.attendance_date and l.status='completed' and at.status::text in ('present','late','absent','excused'))
    from public.class_makeup_attendees m join public.classes c on c.id=m.class_id
    left join public.class_schedules cs on cs.class_id=m.class_id and cs.weekday=extract(isodow from m.attendance_date)::smallint
    join public.students s on s.id=m.student_id and s.status in ('active','재원') where m.attendance_date between p_from and p_to
  ),
  special_lessons as (
    select a.student_id,'special:'||l.id expected_key,case when public.internal_special_student_kind(l.id,a.student_id)='makeup' then '개별 보강' else '추가수업' end,
      coalesce(sub.name,case when public.internal_special_student_kind(l.id,a.student_id)='makeup' then '보강' else '추가수업' end),l.lesson_date,l.starts_at,
      l.status='completed' and a.attendance_status is not null
    from public.teacher_special_lessons l join public.teacher_special_lesson_students a on a.session_id=l.id
    join public.students s on s.id=a.student_id and s.status in ('active','재원') left join public.academy_subjects sub on sub.id=l.subject_id
    where l.lesson_date between p_from and p_to and l.status<>'cancelled'
  ),
  correction_fixed as (
    select a.student_id,'correction:'||a.id||':'||d.occurrence_date||':'||a.start_time expected_key,'첨삭수업',a.subject||' 첨삭',d.occurrence_date,a.start_time,
      exists(select 1 from public.correction_reports r where r.assignment_id=a.id and r.student_id=a.student_id and r.correction_date=d.occurrence_date and r.start_time=a.start_time and r.published and r.attendance_status<>'scheduled')
    from days d join public.correction_assignments a on a.active and a.weekday=extract(isodow from d.occurrence_date)::smallint
      and (a.valid_from is null or a.valid_from<=d.occurrence_date) and (a.valid_until is null or a.valid_until>=d.occurrence_date)
    join public.students s on s.id=a.student_id and s.status in ('active','재원')
    where not exists(select 1 from public.correction_schedule_exceptions x where x.assignment_id=a.id and x.original_date=d.occurrence_date and x.kind in ('move','cancel'))
  ),
  correction_changes as (
    select a.student_id,'correction:'||a.id||':'||x.target_date||':'||x.target_start_time expected_key,'첨삭수업',a.subject||case when x.kind='extra' then ' 추가 첨삭' else ' 첨삭' end,x.target_date,x.target_start_time,
      exists(select 1 from public.correction_reports r where r.assignment_id=a.id and r.student_id=a.student_id and r.correction_date=x.target_date and r.start_time=x.target_start_time and r.published and r.attendance_status<>'scheduled')
    from public.correction_schedule_exceptions x join public.correction_assignments a on a.id=x.assignment_id and a.active
    join public.students s on s.id=a.student_id and s.status in ('active','재원') where x.kind in ('move','extra') and x.target_date between p_from and p_to
  ),
  roster_additions as (
    select distinct o.student_id,'regular:'||o.class_id||':'||o.lesson_date||':'||coalesce((l.starts_at at time zone 'Asia/Seoul')::time,cs.start_time,'00:00'::time) expected_key,
      '정규수업',c.name,o.lesson_date,coalesce((l.starts_at at time zone 'Asia/Seoul')::time,cs.start_time),
      exists(select 1 from public.lessons ll join public.attendance a on a.lesson_id=ll.id and a.student_id=o.student_id where ll.class_id=o.class_id and ll.lesson_date=o.lesson_date and ll.status='completed' and a.status::text in ('present','late','absent','excused'))
    from public.class_lesson_roster_overrides o join public.classes c on c.id=o.class_id
    join public.students s on s.id=o.student_id and s.status in ('active','재원')
    left join public.lessons l on l.class_id=o.class_id and l.lesson_date=o.lesson_date
    left join public.class_schedules cs on cs.class_id=o.class_id and cs.weekday=extract(isodow from o.lesson_date)
    where o.lesson_date between p_from and p_to
      and not exists(select 1 from public.schedule_exceptions x where x.class_id=o.class_id and x.original_date=o.lesson_date and x.kind in ('cancelled','changed','makeup'))
  ),
  scheduled_expected as (
    select * from regular_fixed union select * from regular_replacements union select * from class_makeups
    union select * from roster_additions
    union all select * from special_lessons union all select * from correction_fixed union select * from correction_changes
  ),
 identified as (
 select distinct on (e.student_id,case when split_part(expected_key,':',1) in ('regular','class-makeup') then 'class:'||split_part(expected_key,':',2)||':'||occurrence_date else expected_key end) e.*,split_part(expected_key,':',1) source,split_part(expected_key,':',2)::uuid entity_id
 from scheduled_expected e where not coalesce(completed,false)
 order by e.student_id,case when split_part(expected_key,':',1) in ('regular','class-makeup') then 'class:'||split_part(expected_key,':',2)||':'||occurrence_date else expected_key end,case when kind like '%보강%' then 0 else 1 end,start_time
 ),
 enriched as (
 select e.*,c.id class_id,sp.id session_id,ca.id assignment_id,
 coalesce(case when e.source='special' then sp.ends_at when e.source='correction' then coalesce(cx.target_end_time,ca.end_time) else coalesce((l.ends_at at time zone 'Asia/Seoul')::time,(select max(x.end_time) from public.schedule_exceptions x where x.class_id=c.id and x.replacement_date=e.occurrence_date and x.kind in ('changed','makeup'))) end,
 (select max(sc.end_time) from public.class_schedules sc where sc.class_id=c.id and sc.weekday=extract(isodow from e.occurrence_date) and (e.start_time is null or sc.start_time=e.start_time)),e.start_time+interval '90 minutes','23:59'::time) end_time,
 case when e.source='special' then array[sp.teacher_profile_id]
 when e.source='correction' then array_remove(array[coalesce(ca.tutor_profile_id,ca.teacher_profile_id),ca.supervisor_profile_id],null)||array(select sa.assistant_profile_id from public.correction_slot_assistants sa where sa.weekday=extract(isodow from e.occurrence_date) and sa.start_time=e.start_time)
 else case when l.teacher_profile_id is not null then array[l.teacher_profile_id] else array(select ct.profile_id from public.class_teachers ct where ct.class_id=c.id) end end owner_ids,
 case when e.source='special' then exists(select 1 from public.teacher_special_lesson_students a where a.session_id=sp.id and a.student_id=e.student_id and a.attendance_status is not null)
 when e.source='correction' then exists(select 1 from public.correction_reports r where r.assignment_id=ca.id and r.student_id=e.student_id and r.correction_date=e.occurrence_date and r.start_time=e.start_time and r.attendance_status<>'scheduled')
 else exists(select 1 from public.attendance a where a.lesson_id=l.id and a.student_id=e.student_id and a.status::text in ('present','late','absent','excused')) end has_attendance
 from identified e
 left join public.classes c on e.source in ('regular','class-makeup') and c.id=e.entity_id
 left join lateral(select * from public.lessons ll where ll.class_id=c.id and ll.lesson_date=e.occurrence_date order by ll.starts_at limit 1) l on true
 left join public.teacher_special_lessons sp on e.source='special' and sp.id=e.entity_id
 left join public.correction_assignments ca on e.source='correction' and ca.id=e.entity_id
 left join public.correction_schedule_exceptions cx on cx.assignment_id=ca.id and cx.target_date=e.occurrence_date and cx.target_start_time=e.start_time and cx.kind in ('move','extra')
 where coalesce(l.status,'')<>'cancelled'
 ),
 scoped as (
 select e.*,coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name,p.id) from public.profiles p where p.id=any(e.owner_ids) and p.is_active and p.role in ('admin','sub_admin','teacher','assistant','manager')),'[]'::jsonb) owners
 from enriched e where admin or uid=any(e.owner_ids)
 )
 select coalesce(jsonb_agg(item order by item->>'date',item->>'time',item->>'studentName'),'[]'::jsonb) into result from (
 select distinct jsonb_build_object('key',e.expected_key||':'||s.id,'source',e.source,'kind',e.kind,'title',e.title,'date',e.occurrence_date,'time',to_char(e.start_time,'HH24:MI'),'endTime',to_char(e.end_time,'HH24:MI'),
 'due',((e.occurrence_date+e.end_time) at time zone 'Asia/Seoul')<=now(),
 'studentId',s.id,'studentName',s.name,'classId',e.class_id,'sessionId',e.session_id,'assignmentId',e.assignment_id,'owners',e.owners,
 'reason',case when e.has_attendance then '완료 처리 필요' else '출결 입력 필요' end,
 'requestedAt',(select max(r.requested_at) from public.record_work_requests r where r.recipient_id=uid and r.work_date=e.occurrence_date)) item
 from scoped e join public.students s on s.id=e.student_id
 ) q;
 return result;
end $function$;

CREATE OR REPLACE FUNCTION public.staff_student_attendance_makeup_history(p_student_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_staff() then
    raise exception '교직원만 학생 출결 기록을 확인할 수 있습니다.';
  end if;

  return jsonb_build_object(
    'regularAttendance', coalesce((
      select jsonb_agg(to_jsonb(q) order by q."lessonDate" desc, q.id)
      from (
        select
          a.id,
          l.lesson_date as "lessonDate",
          c.name as "className",
          a.status,
          a.note
        from public.attendance a
        join public.lessons l on l.id = a.lesson_id
        join public.classes c on c.id = l.class_id
        where a.student_id = p_student_id
        order by l.lesson_date desc, a.id
      ) q
    ), '[]'::jsonb),
    'correctionAttendance', coalesce((
      select jsonb_agg(to_jsonb(q) order by q."lessonDate" desc, q."startTime" desc, q.id)
      from (
        select
          r.id,
          r.correction_date as "lessonDate",
          (r.subject || ' 첨삭')::text as "className",
          r.subject,
          r.start_time as "startTime",
          r.attendance_status as status,
          case
            when r.attendance_status = 'late' and r.late_minutes is not null then r.late_minutes || '분 지각'
            when r.attendance_status = 'absent' then coalesce(nullif(r.absence_reason, ''), '결석 사유 없음')
            else null
          end as note
        from public.correction_reports r
        where r.student_id = p_student_id
          and r.attendance_status <> 'scheduled'
        order by r.correction_date desc, r.start_time desc, r.id
      ) q
    ), '[]'::jsonb),
    'makeups', coalesce((
      select jsonb_agg(to_jsonb(q) order by q."scheduledAt" desc, q.id)
      from (
        select
          ('absence:' || ms.id::text) as id,
          c.name as "className",
          l.lesson_date as "missedDate",
          ms.scheduled_at as "scheduledAt",
          ms.ends_at as "endsAt",
          ms.room,
          ms.status::text as status,
          p.display_name as "teacherName",
          ms.note,
          'absence_makeup'::text as "recordKind"
        from public.makeup_sessions ms
        join public.attendance a on a.id = ms.attendance_id
        join public.lessons l on l.id = a.lesson_id
        join public.classes c on c.id = l.class_id
        join public.profiles p on p.id = ms.teacher_profile_id
        where a.student_id = p_student_id

        union all

        select
          ('special:' || sl.id::text) as id,
          case when public.internal_special_student_kind(sl.id,p_student_id) = 'makeup' then '개별 보강' else '추가수업' end as "className",
          null::date as "missedDate",
          ((sl.lesson_date + sl.starts_at) at time zone 'Asia/Seoul') as "scheduledAt",
          ((sl.lesson_date + sl.ends_at) at time zone 'Asia/Seoul') as "endsAt",
          coalesce(sl.room, '') as room,
          case
            when ((sl.lesson_date + sl.ends_at) at time zone 'Asia/Seoul') < now() then 'completed'
            else 'scheduled'
          end as status,
          p.display_name as "teacherName",
          sl.note,
          case when public.internal_special_student_kind(sl.id,p_student_id) = 'makeup' then 'individual_makeup' else 'additional' end as "recordKind"
        from public.teacher_special_lessons sl
        join public.teacher_special_lesson_students ss on ss.session_id = sl.id
        join public.profiles p on p.id = sl.teacher_profile_id
        where ss.student_id = p_student_id
      ) q
    ), '[]'::jsonb)
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.family_previous_homework(p_student_id uuid, p_record_id uuid, p_kind text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare selected_id uuid; current_row record; result text;
begin
 selected_id := public.internal_family_student_id(p_student_id);
 if selected_id is null then raise exception '연결된 학생의 기록만 확인할 수 있습니다.'; end if;
 if p_kind='correction' then
  select r.* into current_row from public.correction_reports r where r.id=p_record_id and r.student_id=selected_id and r.published and r.correction_date<=current_date;
  if not found then raise exception '공개된 첨삭 기록만 확인할 수 있습니다.'; end if;
  select r.homework_instruction into result from public.correction_reports r
  where r.student_id=selected_id and r.published and r.subject=current_row.subject
   and (r.correction_date,r.start_time)<(current_row.correction_date,current_row.start_time)
   and nullif(trim(r.homework_instruction),'') is not null
  order by r.correction_date desc,r.start_time desc,r.id desc limit 1;
 elsif p_kind='lesson' then
  select l.* into current_row from public.lessons l where l.id=p_record_id and l.status='completed' and l.lesson_date<=current_date
   and exists(select 1 from public.attendance a where a.lesson_id=l.id and a.student_id=selected_id);
  if found then
   select coalesce(hr.assigned_homework,l.homework_content,'') into result
   from public.lessons l left join public.lesson_homework_results hr on hr.lesson_id=l.id and hr.student_id=selected_id
   where l.class_id=current_row.class_id and l.status='completed' and l.starts_at<current_row.starts_at and l.lesson_date<=current_date
    and exists(select 1 from public.attendance a where a.lesson_id=l.id and a.student_id=selected_id)
    and nullif(trim(coalesce(hr.assigned_homework,l.homework_content,'')),'') is not null
   order by l.starts_at desc,l.id desc limit 1;
  else
   select l.* into current_row from public.teacher_special_lessons l where l.id=p_record_id and l.status='completed' and l.lesson_date<=current_date
    and exists(select 1 from public.teacher_special_lesson_students a where a.session_id=l.id and a.student_id=selected_id);
   if not found then raise exception '공개된 수업 기록만 확인할 수 있습니다.'; end if;
   select a.assigned_homework into result
   from public.teacher_special_lessons l join public.teacher_special_lesson_students a on a.session_id=l.id and a.student_id=selected_id
   where l.status='completed' and public.internal_special_student_kind(l.id,selected_id)=public.internal_special_student_kind(current_row.id,selected_id) and l.subject_id is not distinct from current_row.subject_id
    and l.teacher_profile_id is not distinct from current_row.teacher_profile_id
    and (l.lesson_date,l.starts_at)<(current_row.lesson_date,current_row.starts_at)
    and nullif(trim(a.assigned_homework),'') is not null
   order by l.lesson_date desc,l.starts_at desc,l.id desc limit 1;
  end if;
 else raise exception '지원하지 않는 기록 종류입니다.';
 end if;
 return coalesce(trim(result),'');
end $function$;

CREATE OR REPLACE FUNCTION public.staff_teacher_special_lessons(p_teacher_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role public.user_role; v_teacher uuid;
begin
  if auth.uid() is null or not public.is_staff() then raise exception '교직원만 확인할 수 있습니다.'; end if;
  v_role:=public.current_user_role();
  v_teacher:=case when v_role in ('admin','teacher','sub_admin') then p_teacher_id else auth.uid() end;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'reminderRecipientIds',coalesce(l.reminder_recipient_ids,array_remove(array[l.teacher_profile_id],null)),'reminderEnabled',l.reminder_enabled,'id',l.id,'date',l.lesson_date,'startTime',l.starts_at,'endTime',l.ends_at,'kind',l.kind,
    'subjectId',l.subject_id,'subject',s.name,'mainSubject',s.main_subject,
    'room',l.room,'note',l.note,'teacherName',p.display_name,'teacherId',l.teacher_profile_id,
    'students',coalesce((select jsonb_agg(jsonb_build_object(
      'id',st.id,'name',st.name,'school',st.school,'grade',st.grade,
      'attendanceStatus',a.attendance_status,'lessonKind',coalesce(a.lesson_kind,l.kind),'makeupSource',a.makeup_source,'makeupSourceId',a.makeup_source_id
    ) order by st.name)
      from public.teacher_special_lesson_students a
      join public.students st on st.id=a.student_id
      where a.session_id=l.id),'[]'::jsonb)
  ) order by l.lesson_date,l.starts_at)
  from public.teacher_special_lessons l
  join public.profiles p on p.id=l.teacher_profile_id
  left join public.academy_subjects s on s.id=l.subject_id
  where v_teacher is null or l.teacher_profile_id=v_teacher),'[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION public.staff_special_lesson_board(p_session_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_staff() or not exists(
    select 1 from public.teacher_special_lessons l
    where l.id=p_session_id and (l.teacher_profile_id=auth.uid() or public.current_user_role()='admin')
  ) then raise exception '확인할 수 없는 수업입니다.'; end if;
  return (select jsonb_build_object(
    'notice',coalesce(l.class_notice,''),
    'state',coalesce(l.status,'draft'),
    'students',coalesce((select jsonb_agg(jsonb_build_object(
      'lessonKind',coalesce(a.lesson_kind,l.kind),'id',s.id,'name',s.name,'school',s.school,'grade',s.grade,
      'status',a.attendance_status,'lateMinutes',a.late_minutes,'absenceReason',a.absence_reason,
      'lessonContent',coalesce(a.lesson_content,''),
      'assignedHomework',coalesce(a.assigned_homework,''),
      'inspectionStatus',coalesce(a.inspection_status,''),
      'inspectionNote',coalesce(a.inspection_note,''),
      'previousHomework',coalesce((
        select prior_a.assigned_homework
        from public.teacher_special_lesson_students prior_a
        join public.teacher_special_lessons prior_l on prior_l.id=prior_a.session_id
        where prior_a.student_id=s.id and prior_l.teacher_profile_id=l.teacher_profile_id
          and prior_l.lesson_date<l.lesson_date and nullif(trim(prior_a.assigned_homework),'') is not null
        order by prior_l.lesson_date desc,prior_l.starts_at desc limit 1
      ),''),
      'exam',coalesce((select jsonb_build_object(
        'examType',coalesce(e.exam_type,''),'examTitle',coalesce(e.exam_title,''),
        'score',e.score,'maxScore',e.max_score,'evaluation',coalesce(e.evaluation,'')
      ) from public.teacher_special_lesson_exam_results e
        where e.session_id=l.id and e.student_id=s.id),'{}'::jsonb)
    ) order by s.name)
      from public.teacher_special_lesson_students a
      join public.students s on s.id=a.student_id
      where a.session_id=l.id),'[]'::jsonb)
  ) from public.teacher_special_lessons l where l.id=p_session_id);
end $function$;
create or replace function public.internal_special_makeup_board_overlay(p_board jsonb)
returns jsonb language sql stable security invoker set search_path=public as $$
 select jsonb_set(p_board,'{items}',coalesce(jsonb_agg(
 case when linked.session_id is null then item else item||jsonb_build_object(
 'linkedSpecialId',linked.session_id,'sessionId',linked.session_id,'teacherId',l.teacher_profile_id,'teacherName',p.display_name,
 'scheduledAt',(l.lesson_date+l.starts_at) at time zone 'Asia/Seoul','endsAt',(l.lesson_date+l.ends_at) at time zone 'Asia/Seoul','room',l.room,
 'status',case when l.status='completed' and linked.attendance_status in ('present','late') then 'completed' else 'scheduled' end) end
 order by ordinal),'[]'::jsonb))
 from jsonb_array_elements(p_board->'items') with ordinality rows(item,ordinal)
 left join public.teacher_special_lesson_students linked on item->>'recordKind'='absence' and linked.student_id=(item->>'studentId')::uuid
 and linked.makeup_source_id=(item->>'sourceId')::uuid
 and linked.makeup_source=case when item->>'source' in ('regular','class') then 'regular' when item->>'source'='correction' then 'correction' else 'special' end
 left join public.teacher_special_lessons l on l.id=linked.session_id left join public.profiles p on p.id=l.teacher_profile_id
 where not(item->>'recordKind'='schedule' and exists(select 1 from public.teacher_special_lesson_students a where a.session_id::text=item->>'sessionId' and a.student_id::text=item->>'studentId' and a.makeup_source_id is not null))
$$;
revoke all on function public.internal_special_makeup_board_overlay(jsonb) from public,anon,authenticated;
CREATE OR REPLACE FUNCTION public.absence_makeup_board()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role public.user_role;
begin
  if not public.is_staff() or public.current_user_role()='assistant' then raise exception '결석·보강 조회 권한이 없습니다.'; end if;
  v_role:=public.current_user_role();
  return public.internal_special_makeup_board_overlay(jsonb_build_object(
    'isStaff',true,'role',v_role,
    'teachers',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name) from public.profiles p where p.is_active and p.role in ('admin','teacher','sub_admin','manager') and (v_role='admin' or p.id=auth.uid())),'[]'::jsonb),
    'items',coalesce((select jsonb_agg(row_data order by sort_date desc,student_name) from (
      select jsonb_build_object('attendanceId',a.id,'sourceId',a.id,'recordKind','absence','studentId',st.id,'studentName',st.name,'classId',c.id,'className',c.name,'subjectId',c.subject_id,'subjectName',coalesce(sub.name,c.subject,'과목 미지정'),'missedDate',l.lesson_date,'attendanceNote',coalesce(a.absence_reason,a.note),'sessionId',ms.id,'teacherId',ms.teacher_profile_id,'teacherName',tp.display_name,'scheduledAt',ms.scheduled_at,'endsAt',ms.ends_at,'room',ms.room,'status',ms.status,'note',ms.note,'source',case when exists(select 1 from public.class_makeup_attendees cm where cm.class_id=c.id and cm.student_id=st.id and cm.attendance_date=l.lesson_date) then 'class' else 'regular' end) row_data,
        coalesce(ms.scheduled_at,l.starts_at) sort_date,st.name student_name
      from public.attendance a join public.lessons l on l.id=a.lesson_id join public.classes c on c.id=l.class_id join public.students st on st.id=a.student_id left join public.academy_subjects sub on sub.id=c.subject_id left join public.makeup_sessions ms on ms.attendance_id=a.id left join public.profiles tp on tp.id=ms.teacher_profile_id
      where (a.status='absent' or ms.id is not null) and (v_role='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid()))
      union all
      select jsonb_build_object('attendanceId',null,'sourceId',r.id,'recordKind','absence','studentId',st.id,'studentName',st.name,'classId',scope.class_id,'className',coalesce(scope.class_name,'첨삭수업'),'subjectId',scope.subject_id,'subjectName',coalesce(r.subject,'과목 미지정'),'missedDate',r.correction_date,'attendanceNote',r.absence_reason,'sessionId',sm.id,'teacherId',sm.teacher_profile_id,'teacherName',tp.display_name,'scheduledAt',sm.scheduled_at,'endsAt',sm.ends_at,'room',sm.room,'status',sm.status,'note',sm.note,'source','correction') row_data,
        coalesce(sm.scheduled_at,((r.correction_date+r.start_time) at time zone 'Asia/Seoul')) sort_date,st.name student_name
      from public.correction_reports r join public.students st on st.id=r.student_id left join public.source_makeup_sessions sm on sm.source_type='correction' and sm.source_id=r.id and sm.student_id=r.student_id left join public.profiles tp on tp.id=sm.teacher_profile_id
      left join lateral (select c.id class_id,c.name class_name,c.subject_id from public.enrollments e join public.classes c on c.id=e.class_id where e.student_id=st.id and e.status='active' and c.active and (c.subject=r.subject or exists(select 1 from public.academy_subjects su where su.id=c.subject_id and su.name=r.subject)) order by c.name limit 1) scope on true
      where r.attendance_status='absent' and (v_role='admin' or exists(select 1 from public.correction_assignments ca where ca.id=r.assignment_id and (ca.tutor_profile_id=auth.uid() or ca.supervisor_profile_id=auth.uid())) or exists(select 1 from public.class_teachers ct where ct.class_id=scope.class_id and ct.profile_id=auth.uid()))
      union all
      select jsonb_build_object('attendanceId',null,'sourceId',sl.id,'recordKind','absence','studentId',st.id,'studentName',st.name,'classId',scope.class_id,'className',coalesce(scope.class_name,case when public.internal_special_student_kind(sl.id,ss.student_id)='makeup' then '개별 보강' else '추가수업' end),'subjectId',sl.subject_id,'subjectName',coalesce(sub.name,'과목 미지정'),'missedDate',sl.lesson_date,'attendanceNote',ss.absence_reason,'sessionId',sm.id,'teacherId',sm.teacher_profile_id,'teacherName',coalesce(tp.display_name,owner.display_name),'scheduledAt',sm.scheduled_at,'endsAt',sm.ends_at,'room',coalesce(sm.room,sl.room),'status',sm.status,'note',sm.note,'source',case when public.internal_special_student_kind(sl.id,ss.student_id)='makeup' then 'individual' else 'additional' end) row_data,
        coalesce(sm.scheduled_at,((sl.lesson_date+sl.starts_at) at time zone 'Asia/Seoul')) sort_date,st.name student_name
      from public.teacher_special_lessons sl join public.teacher_special_lesson_students ss on ss.session_id=sl.id join public.students st on st.id=ss.student_id left join public.academy_subjects sub on sub.id=sl.subject_id left join public.source_makeup_sessions sm on sm.source_type='special' and sm.source_id=sl.id and sm.student_id=st.id left join public.profiles tp on tp.id=sm.teacher_profile_id left join public.profiles owner on owner.id=sl.teacher_profile_id
      left join lateral (select c.id class_id,c.name class_name from public.enrollments e join public.classes c on c.id=e.class_id where e.student_id=st.id and e.status='active' and c.active and (sl.subject_id is null or c.subject_id=sl.subject_id) order by c.name limit 1) scope on true
      where ss.attendance_status='absent' and (v_role='admin' or sl.teacher_profile_id=auth.uid() or exists(select 1 from public.class_teachers ct where ct.class_id=scope.class_id and ct.profile_id=auth.uid()))
      union all
      select jsonb_build_object('attendanceId',null,'sourceId',null,'recordKind','schedule','studentId',st.id,'studentName',st.name,'classId',c.id,'className',c.name,'subjectId',c.subject_id,'subjectName',coalesce(sub.name,c.subject,'과목 미지정'),'missedDate',null,'attendanceNote',null,'sessionId',concat('class:',m.class_id,':',m.attendance_date),'teacherId',coalesce(l.teacher_profile_id,m.created_by),'teacherName',coalesce(lp.display_name,cp.display_name),'scheduledAt',coalesce(l.starts_at,((m.attendance_date+coalesce(sched.start_time,'18:00'::time)) at time zone 'Asia/Seoul')),'endsAt',coalesce(l.ends_at,((m.attendance_date+coalesce(sched.end_time,'20:00'::time)) at time zone 'Asia/Seoul')),'room',coalesce(l.room,c.room),'status',case when l.id is not null and (exists(select 1 from public.attendance ca where ca.lesson_id=l.id and ca.student_id=st.id) or nullif(trim(l.lesson_content),'') is not null or nullif(trim(l.homework_content),'') is not null or nullif(trim(l.exam_content),'') is not null) then 'completed' else 'scheduled' end,'note',null,'source','class') row_data,
        coalesce(l.starts_at,((m.attendance_date+coalesce(sched.start_time,'18:00'::time)) at time zone 'Asia/Seoul')) sort_date,st.name student_name
      from public.class_makeup_attendees m join public.classes c on c.id=m.class_id join public.students st on st.id=m.student_id left join public.academy_subjects sub on sub.id=c.subject_id left join lateral (select lesson.* from public.lessons lesson where lesson.class_id=m.class_id and lesson.lesson_date=m.attendance_date order by lesson.starts_at limit 1) l on true left join lateral (select cs.start_time,cs.end_time from public.class_schedules cs where cs.class_id=m.class_id order by cs.start_time limit 1) sched on true left join public.profiles lp on lp.id=l.teacher_profile_id left join public.profiles cp on cp.id=m.created_by
      where not exists(select 1 from public.attendance ca where ca.lesson_id=l.id and ca.student_id=st.id and ca.status='absent') and (v_role='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid()))
      union all
      select jsonb_build_object('attendanceId',null,'sourceId',sl.id,'recordKind','schedule','studentId',st.id,'studentName',st.name,'classId',scope.class_id,'className',coalesce(scope.class_name,'개별 보강'),'subjectId',sl.subject_id,'subjectName',coalesce(sub.name,'과목 미지정'),'missedDate',null,'attendanceNote',null,'sessionId',sl.id,'teacherId',sl.teacher_profile_id,'teacherName',tp.display_name,'scheduledAt',((sl.lesson_date+sl.starts_at) at time zone 'Asia/Seoul'),'endsAt',((sl.lesson_date+sl.ends_at) at time zone 'Asia/Seoul'),'room',sl.room,'status',case when sl.status='completed' then 'completed' else 'scheduled' end,'note',sl.note,'source','individual') row_data,
        ((sl.lesson_date+sl.starts_at) at time zone 'Asia/Seoul') sort_date,st.name student_name
      from public.teacher_special_lessons sl join public.teacher_special_lesson_students ss on ss.session_id=sl.id join public.students st on st.id=ss.student_id join public.profiles tp on tp.id=sl.teacher_profile_id left join public.academy_subjects sub on sub.id=sl.subject_id left join lateral (select c.id class_id,c.name class_name from public.enrollments e join public.classes c on c.id=e.class_id where e.student_id=st.id and e.status='active' and c.active and (sl.subject_id is null or c.subject_id=sl.subject_id) order by c.name limit 1) scope on true
      where public.internal_special_student_kind(sl.id,ss.student_id)='makeup' and ss.attendance_status is distinct from 'absent' and (v_role='admin' or sl.teacher_profile_id=auth.uid() or exists(select 1 from public.class_teachers ct where ct.class_id=scope.class_id and ct.profile_id=auth.uid()))
    ) rows),'[]'::jsonb)
  ));
end $function$;
create or replace function public.staff_special_absence_options(p_student_id uuid,p_session_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare board jsonb;
begin
 board:=public.absence_makeup_board();
 return coalesce((select jsonb_agg(jsonb_build_object('source',case when r->>'source' in ('regular','class') then 'regular' when r->>'source'='correction' then 'correction' else 'special' end,
 'sourceId',r->>'sourceId','date',r->>'missedDate','title',r->>'className','subjectId',r->>'subjectId') order by r->>'missedDate' desc)
 from jsonb_array_elements(board->'items') r where r->>'recordKind'='absence' and r->>'studentId'=p_student_id::text
 and (r->>'status' is null or r->>'status'='cancelled' or r->>'linkedSpecialId'=p_session_id::text)
 and r->>'sourceId' is distinct from p_session_id::text),'[]'::jsonb);
end $$;
revoke all on function public.staff_special_absence_options(uuid,uuid) from public,anon;
grant execute on function public.staff_special_absence_options(uuid,uuid) to authenticated;

create or replace function public.staff_save_mixed_special_lesson(p_values jsonb,p_reminder_enabled boolean,p_students jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare sid uuid; row_data jsonb; options jsonb; old_id uuid:=nullif(p_values->>'p_id','')::uuid; source text; source_id uuid; student uuid; teacher uuid:=coalesce(nullif(p_values->>'p_teacher_id','')::uuid,auth.uid());
begin
 if auth.uid() is null or not public.is_staff() or (public.current_user_role()<>'admin' and teacher<>auth.uid()) then raise exception '저장 권한이 없습니다.'; end if;
 if old_id is not null and not exists(select 1 from teacher_special_lessons where id=old_id and (teacher_profile_id=auth.uid() or public.current_user_role()='admin')) then raise exception '수정 권한이 없습니다.'; end if;
 if jsonb_typeof(p_students) is distinct from 'array' or jsonb_array_length(p_students)=0 then raise exception '참여 학생을 선택해 주세요.'; end if;
 if (select count(*)<>count(distinct value->>'studentId') from jsonb_array_elements(p_students)) then raise exception '학생이 중복 선택되었습니다.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('mixed-special-lessons',0));
 if old_id is not null then
  if jsonb_typeof(p_values->'p_expected_student_ids')='array' and
   (select coalesce(jsonb_agg(student_id::text order by student_id::text),'[]'::jsonb) from teacher_special_lesson_students where session_id=old_id)
   is distinct from (select coalesce(jsonb_agg(value order by value),'[]'::jsonb) from jsonb_array_elements_text(p_values->'p_expected_student_ids')) then
   raise exception '참여 학생이 변경되었습니다. 창을 다시 열어 확인해 주세요.';
  end if;
  if exists(select 1 from teacher_special_lesson_students a where a.session_id=old_id
    and not exists(select 1 from jsonb_array_elements(p_students) v where v->>'studentId'=a.student_id::text)
    and (a.attendance_status is not null or nullif(trim(a.lesson_content),'') is not null or nullif(trim(a.assigned_homework),'') is not null
      or exists(select 1 from teacher_special_lesson_exam_results e where e.session_id=a.session_id and e.student_id=a.student_id))) then
   raise exception '수업 기록이 있는 학생은 제외할 수 없습니다. 기존 기록을 먼저 확인해 주세요.';
  end if;
 end if;

 for row_data in select value from jsonb_array_elements(p_students) loop
  student:=(row_data->>'studentId')::uuid;
  if student is null or row_data->>'kind' is null or row_data->>'kind' not in ('makeup','additional') then raise exception '학생별 수업 구분을 확인해 주세요.'; end if;
  source:=nullif(row_data->>'source','');source_id:=nullif(row_data->>'sourceId','')::uuid;
  if (source is null)<>(source_id is null) or (source is not null and row_data->>'kind'<>'makeup') then raise exception '보강 학생의 결석 연결을 확인해 주세요.'; end if;
  if source_id is not null then
   options:=public.staff_special_absence_options(student,old_id);
   if not exists(select 1 from jsonb_array_elements(options) o where o->>'source'=source and o->>'sourceId'=source_id::text and (o->>'date')::date<=(p_values->>'p_date')::date) then raise exception '이미 보강이 잡혔거나 연결할 수 없는 결석 기록입니다.'; end if;
  end if;
 end loop;
 p_values:=p_values||jsonb_build_object('p_student_ids',(select jsonb_agg(value->>'studentId') from jsonb_array_elements(p_students)));
 sid:=public.staff_save_special_with_reminder(p_values,p_reminder_enabled);
 for row_data in select value from jsonb_array_elements(p_students) loop
  update public.teacher_special_lesson_students set lesson_kind=row_data->>'kind',makeup_source=nullif(row_data->>'source',''),makeup_source_id=nullif(row_data->>'sourceId','')::uuid
  where session_id=sid and student_id=(row_data->>'studentId')::uuid;
 end loop;
 return sid;
end $$;
revoke all on function public.staff_save_mixed_special_lesson(jsonb,boolean,jsonb) from public,anon;
grant execute on function public.staff_save_mixed_special_lesson(jsonb,boolean,jsonb) to authenticated;

-- Prevent older absence-booking screens from booking an already linked absence.
create or replace function public.guard_linked_special_makeup()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 perform pg_advisory_xact_lock(hashtextextended('mixed-special-lessons',0));
 if new.status='cancelled' then return new; end if;
 if tg_table_name='makeup_sessions' then
  if exists(select 1 from teacher_special_lesson_students where makeup_source='regular' and makeup_source_id=new.attendance_id) then
   raise exception '이미 수업에 연결된 결석입니다. 연결된 보강·추가수업에서 수정해 주세요.';
  end if;
 else
  if exists(select 1 from teacher_special_lesson_students where makeup_source=new.source_type and makeup_source_id=new.source_id and student_id=new.student_id) then
   raise exception '이미 수업에 연결된 결석입니다. 연결된 보강·추가수업에서 수정해 주세요.';
  end if;
 end if;
 return new;
end $$;
revoke all on function public.guard_linked_special_makeup() from public,anon,authenticated;
create trigger guard_linked_special_makeup before insert or update on public.makeup_sessions for each row execute function public.guard_linked_special_makeup();
create trigger guard_linked_special_makeup before insert or update on public.source_makeup_sessions for each row execute function public.guard_linked_special_makeup();
