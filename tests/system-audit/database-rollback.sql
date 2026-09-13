-- Read-only assertions and temporary reference functions; always rolls back.
begin;
CREATE OR REPLACE FUNCTION pg_temp.reference_ready(p_from date, p_to date)
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
  readiness as (
    select student_id,count(*)::integer expected_count,count(*) filter(where completed)::integer completed_count,
      coalesce(jsonb_agg(jsonb_build_object('kind',kind,'title',title,'date',occurrence_date,'time',to_char(start_time,'HH24:MI')) order by occurrence_date,start_time,title) filter(where not completed),'[]'::jsonb) missing_items
    from resolved_expected group by student_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'studentId',s.id,'studentName',s.name,'school',coalesce(s.school,''),'grade',coalesce(s.grade,''),
    'expectedCount',r.expected_count,'completedCount',r.completed_count,'complete',r.completed_count=r.expected_count,'missingItems',r.missing_items,
    'lessons',public.staff_learning_report_source(s.id,p_from,p_to),'recipient',public.staff_alimtalk_recipient(s.id)
  ) order by (r.completed_count=r.expected_count) desc,s.name),'[]'::jsonb) into result
  from readiness r join public.students s on s.id=r.student_id where r.expected_count>0;
  return result;
end $function$;
CREATE OR REPLACE FUNCTION pg_temp.reference_today(p_student_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare base jsonb; sid uuid; today date := (now() at time zone 'Asia/Seoul')::date; result jsonb;
begin
  base:=public.family_live_dashboard(p_student_id);
  sid:=nullif(base->'selectedStudent'->>'id','')::uuid;
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
CREATE OR REPLACE FUNCTION pg_temp.reference_september(p_student_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare base jsonb; sid uuid; today date := '2026-09-12'::date; result jsonb;
begin
  base:=public.family_live_dashboard(p_student_id);
  sid:=nullif(base->'selectedStudent'->>'id','')::uuid;
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
CREATE OR REPLACE FUNCTION pg_temp.current_september(p_student_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sid uuid; today date := '2026-09-12'::date; result jsonb;
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
do $test$
declare d date; old_rows jsonb; new_rows jsonb; g record; role_fixture record;
admin_id uuid; denied boolean; e public.enrollments%rowtype;
begin
select id into admin_id from public.profiles where role='admin' and is_active limit 1;
if admin_id is null then raise exception 'An active admin fixture is required'; end if;
perform set_config('request.jwt.claim.sub',admin_id::text,true);
for d in select generate_series('2026-09-07'::date,'2026-09-13'::date,interval '1 day')::date loop
 select jsonb_object_agg(x->>'studentId',x) into old_rows from jsonb_array_elements(pg_temp.reference_ready(d,d)) x;
 select jsonb_object_agg(x->>'studentId',x) into new_rows from jsonb_array_elements(public.staff_alimtalk_ready_students(d,d)) x;
 if old_rows is distinct from new_rows then raise exception 'daily mismatch %',d; end if;
end loop;
select jsonb_object_agg(x->>'studentId',x) into old_rows from jsonb_array_elements(pg_temp.reference_ready('2026-09-07','2026-09-13')) x;
select jsonb_object_agg(x->>'studentId',x) into new_rows from jsonb_array_elements(public.staff_alimtalk_ready_students('2026-09-07','2026-09-13')) x;
if old_rows is distinct from new_rows then raise exception 'weekly mismatch'; end if;
for g in select distinct p.id profile_id,s.id student_id from public.profiles p join public.guardians gu on gu.profile_id=p.id join public.student_guardians sg on sg.guardian_id=gu.id join public.students s on s.id=sg.student_id where p.is_active loop
 perform set_config('request.jwt.claim.sub',g.profile_id::text,true);
 new_rows:=public.family_home_snapshot(g.student_id);
 if pg_temp.reference_today(g.student_id) is distinct from new_rows->'todayLessons' or public.family_live_dashboard(g.student_id) is distinct from new_rows->'dashboard' then raise exception 'family mismatch'; end if;
 if pg_temp.reference_september(g.student_id) is distinct from pg_temp.current_september(g.student_id) then raise exception 'nonempty family mismatch'; end if;
 if exists(select 1 from public.student_schedule_assignments where student_id=g.student_id) and exists(select 1 from jsonb_array_elements(new_rows->'dashboard'->'weekClasses') x where not exists(select 1 from public.student_schedule_assignments a where a.student_id=g.student_id and a.class_schedule_id=(x->>'id')::uuid)) then raise exception 'unassigned weekday visible'; end if;
 if exists(select 1 from jsonb_array_elements(pg_temp.current_september(g.student_id)) x where x->>'kind'='special' and x->>'label'='개별수업') then raise exception 'additional label mismatch'; end if;
end loop;
for role_fixture in select distinct on(role) id,role from public.profiles where is_active order by role,id loop
 perform set_config('request.jwt.claim.sub',role_fixture.id::text,true);
 denied:=false;
 begin perform public.admin_account_help_target(role_fixture.id); exception when insufficient_privilege then denied:=true; end;
 if denied<>(role_fixture.role<>'admin') then raise exception 'admin access mismatch %',role_fixture.role; end if;
 denied:=false;
 begin perform public.staff_alimtalk_ready_students('2026-09-13','2026-09-13'); exception when others then denied:=true; end;
 if denied<>(role_fixture.role not in ('admin','sub_admin')) then raise exception 'alimtalk access mismatch %',role_fixture.role; end if;
 denied:=false;
 begin perform public.family_home_snapshot(null); exception when others then denied:=true; end;
 if denied<>(role_fixture.role not in ('guardian','student')) then raise exception 'family access mismatch %',role_fixture.role; end if;
end loop;
perform set_config('request.jwt.claim.sub','',true);
denied:=false;
begin perform public.admin_account_help_target(null); exception when insufficient_privilege then denied:=true; end;
if not denied then raise exception 'missing identity accepted'; end if;
if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname in ('admin_account_help_target','admin_prepare_account_help','admin_finish_account_help','enqueue_family_notification','enqueue_learning_report_notification','refresh_tuition_charge_status','family_home_snapshot') and has_function_privilege('anon',p.oid,'execute')) then raise exception 'anonymous execute still granted'; end if;
if exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and proname in ('enqueue_family_notification','enqueue_learning_report_notification','refresh_tuition_charge_status','internal_family_student_id','internal_alimtalk_report_sources') and has_function_privilege('authenticated',p.oid,'execute')) then raise exception 'internal execute still granted'; end if;
select * into e from public.enrollments where status='active' limit 1;
begin
 insert into public.enrollments(student_id,class_id,status,started_on) values(e.student_id,e.class_id,'active',current_date+1);
 raise exception 'duplicate active enrollment accepted';
exception when unique_violation then null;
end;
end $test$;
select 'PASS: authorization, enrollment uniqueness, family visibility, daily/weekly parity' result;
rollback;
