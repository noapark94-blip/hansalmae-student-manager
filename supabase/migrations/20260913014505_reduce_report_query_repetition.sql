create or replace function public.internal_family_student_id(p_student_id uuid)
returns uuid language plpgsql stable security definer set search_path=public as $resolve$
declare viewer_role public.user_role; selected_id uuid;
begin
  viewer_role := public.current_user_role();
  if viewer_role is null or viewer_role not in ('student','guardian') then raise exception '학생 또는 학부모 계정만 가족 대시보드를 확인할 수 있습니다.'; end if;
  if viewer_role='student' then
    select id into selected_id from public.students where profile_id=auth.uid();
    if p_student_id is not null and p_student_id is distinct from selected_id then raise exception '본인 학생 정보만 확인할 수 있습니다.'; end if;
  else
    if p_student_id is null then select s.id into selected_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() order by sg.is_primary desc,s.name limit 1;
    else
      select s.id into selected_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() and s.id=p_student_id;
      if selected_id is null then raise exception '연결된 자녀만 확인할 수 있습니다.'; end if;
    end if;
  end if;

return selected_id;
end $resolve$;
revoke all on function public.internal_family_student_id(uuid) from public,anon,authenticated;
grant execute on function public.internal_family_student_id(uuid) to service_role;

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
    from public.lessons l join public.classes c on c.id=l.class_id left join public.profiles p on p.id=l.teacher_profile_id left join public.attendance a on a.lesson_id=l.id and a.student_id=sid where l.lesson_date=today and (public.student_attends_class_on(sid,c.id,today) or a.id is not null)
    union all
    select 'special:'||l.id::text,'special',case l.kind when 'makeup' then '보강' when 'extra' then '추가수업' when 'additional' then '추가수업' else '개별수업' end,coalesce(s.name,'과목 미지정'),to_char(l.starts_at,'HH24:MI'),to_char(l.ends_at,'HH24:MI'),coalesce(p.display_name,''),coalesce(l.room,''),ss.attendance_status
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

create or replace function public.family_home_snapshot(p_student_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public as $home$
declare dashboard jsonb; today_lessons jsonb;
begin
dashboard:=public.family_live_dashboard(p_student_id);
today_lessons:=public.family_today_lessons(p_student_id);
return jsonb_build_object('dashboard',dashboard,'todayLessons',today_lessons);
end $home$;
revoke all on function public.family_home_snapshot(uuid) from public,anon;
grant execute on function public.family_home_snapshot(uuid) to authenticated;

create or replace function public.internal_alimtalk_report_sources(p_student_ids uuid[], p_from date,p_to date)
returns table(student_id uuid,lessons jsonb)
language sql stable security definer set search_path=public as $batch$
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
      'lessonContent', coalesce(nullif(trim(hr.lesson_content),''), l.lesson_content, ''),
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
          and er.student_id = a.student_id
          and (
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
 and exists(select 1 from public.enrollments e where e.class_id=c.id and e.student_id=a.student_id and e.started_on<=l.lesson_date and (e.ended_on is null or e.ended_on>=l.lesson_date))
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
$batch$;
revoke all on function public.internal_alimtalk_report_sources(uuid[],date,date) from public,anon,authenticated;
grant execute on function public.internal_alimtalk_report_sources(uuid[],date,date) to service_role;

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
    select a.student_id,'special:'||l.id expected_key,case when l.kind='makeup' then '개별 보강' else '추가수업' end,
      coalesce(sub.name,case when l.kind='makeup' then '보강' else '추가수업' end),l.lesson_date,l.starts_at,
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
  expected as (
    select * from regular_fixed union select * from regular_replacements union select * from class_makeups
    union all select * from special_lessons union all select * from correction_fixed union select * from correction_changes
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
