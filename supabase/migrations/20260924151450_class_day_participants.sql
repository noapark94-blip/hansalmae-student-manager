-- Date-scoped participation: retain every original attendance/exam/homework row.
create table public.class_lesson_participation (
 class_id uuid not null references public.classes(id) on delete cascade,
 lesson_date date not null,
 student_id uuid not null references public.students(id) on delete cascade,
 excluded boolean not null default false,
 reason text not null default '' check (char_length(reason)<=120),
 updated_by uuid references public.profiles(id) on delete set null,
 updated_at timestamptz not null default clock_timestamp(),
 primary key(class_id,lesson_date,student_id)
);
create index class_lesson_participation_student_idx on public.class_lesson_participation(student_id,lesson_date);
create index class_lesson_participation_actor_idx on public.class_lesson_participation(updated_by) where updated_by is not null;
alter table public.class_lesson_participation enable row level security;
revoke all on public.class_lesson_participation from public,anon,authenticated;
create policy staff_participation_read on public.class_lesson_participation for select to authenticated
using(public.is_staff() and (public.current_user_role()='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=class_lesson_participation.class_id and ct.profile_id=auth.uid())));
-- Only authorized RPCs expose staff-only reasons. No direct family access.
create or replace function public.internal_class_student_excluded(p_student uuid,p_class uuid,p_date date)
returns boolean language sql stable security invoker set search_path=public as $$
 select exists(select 1 from public.class_lesson_participation x where x.class_id=p_class and x.lesson_date=p_date and x.student_id=p_student and x.excluded)
$$;
revoke all on function public.internal_class_student_excluded(uuid,uuid,date) from public,anon,authenticated;
create or replace function public.internal_class_participation_version(p_class uuid,p_date date)
returns text language sql stable security invoker set search_path=public as $$
 select md5(coalesce(jsonb_agg(jsonb_build_array(student_id,excluded,reason,updated_at) order by student_id)::text,'[]'))
 from public.class_lesson_participation where class_id=p_class and lesson_date=p_date
$$;
revoke all on function public.internal_class_participation_version(uuid,date) from public,anon,authenticated;

-- These private views feed existing authorized report functions; originals remain editable.
create view public.internal_participating_attendance with (security_invoker=true) as
 select a.* from public.attendance a join public.lessons l on l.id=a.lesson_id
 where not public.internal_class_student_excluded(a.student_id,l.class_id,l.lesson_date);
create view public.internal_participating_exams with (security_invoker=true) as
 select a.* from public.lesson_exam_results a join public.lessons l on l.id=a.lesson_id
 where not public.internal_class_student_excluded(a.student_id,l.class_id,l.lesson_date);
create view public.internal_participating_homework with (security_invoker=true) as
 select a.* from public.lesson_homework_results a join public.lessons l on l.id=a.lesson_id
 where not public.internal_class_student_excluded(a.student_id,l.class_id,l.lesson_date);
revoke all on public.internal_participating_attendance,public.internal_participating_exams,public.internal_participating_homework from public,anon,authenticated;

create or replace function public.staff_set_class_lesson_participants(p_class_id uuid,p_date date,p_changes jsonb,p_expected_version text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb; sid uuid; ids uuid[]:='{}'; is_excluded boolean; why text; snap jsonb; draft_row jsonb; live_row jsonb;
begin
 if auth.uid() is null or not coalesce(public.is_staff(),false) or
 (public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid())) then
  raise exception '담당 클래스의 수업 대상만 변경할 수 있습니다.';
 end if;
 if p_date is null or jsonb_typeof(p_changes) is distinct from 'array' or jsonb_array_length(p_changes)>300 then raise exception '변경할 수업 대상을 확인해 주세요.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_class_id::text||':'||p_date::text,0));
 if p_expected_version is distinct from public.internal_class_participation_version(p_class_id,p_date) then
  raise exception '다른 선생님이 수업 대상을 변경했습니다. 최신 명단을 확인해 주세요.';
 end if;
 for r in select value from jsonb_array_elements(p_changes) order by value->>'studentId' loop
  sid:=(r->>'studentId')::uuid;
  if sid is null or sid=any(ids) or jsonb_typeof(r->'excluded') is distinct from 'boolean' then raise exception '변경할 학생을 확인해 주세요.'; end if;
  ids:=array_append(ids,sid);is_excluded:=(r->>'excluded')::boolean;why:=trim(coalesce(r->>'reason',''));
  perform pg_advisory_xact_lock(hashtextextended('alimtalk-source:'||sid||':'||p_date,0));
  if char_length(why)>120 then raise exception '변경 사유는 120자 이내로 입력해 주세요.'; end if;
  if not public.student_attends_class_on(sid,p_class_id,p_date) and not exists(select 1 from public.class_lesson_participation x where x.class_id=p_class_id and x.lesson_date=p_date and x.student_id=sid) then
   raise exception '이 날짜의 수업 명단에 없는 학생입니다.';
  end if;
  if is_excluded then
   snap:=public.staff_class_edit_snapshot(p_class_id,p_date);
   select value into draft_row from jsonb_array_elements(coalesce(snap->'revision'->'payload'->'rows','[]')) where value->>'studentId'=sid::text;
   select value into live_row from jsonb_array_elements(snap->'day'->'students') where value->>'id'=sid::text;
   if draft_row is not null and (
    nullif(draft_row->>'status','') is distinct from (case when live_row->>'status'='excused' then 'absent' else nullif(live_row->>'status','') end)
    or nullif(draft_row->>'lateMinutes','') is distinct from nullif(live_row->>'lateMinutes','')
    or coalesce(draft_row->>'absenceReason','') is distinct from coalesce(live_row->>'absenceReason','')
    or coalesce(draft_row->>'note','') is distinct from coalesce(live_row->>'note','')
   ) then raise exception '수정 중인 출결이 있습니다. 출결 수정 내용을 먼저 반영한 뒤 수업 대상을 변경해 주세요. 임시저장 내용은 유지됩니다.'; end if;
  end if;
  if is_excluded and exists(select 1 from public.attendance a join public.lessons l on l.id=a.lesson_id
   where a.student_id=sid and l.class_id=p_class_id and l.lesson_date=p_date and (
    exists(select 1 from public.makeup_sessions m where m.attendance_id=a.id and m.status<>'cancelled')
    or exists(select 1 from public.teacher_special_lesson_students s where s.makeup_source='regular' and s.makeup_source_id=a.id))) then
   raise exception '연결된 보강이 있는 학생입니다. 보강 일정을 먼저 확인해 주세요.';
  end if;
  insert into public.class_lesson_participation(class_id,lesson_date,student_id,excluded,reason,updated_by)
  values(p_class_id,p_date,sid,is_excluded,why,auth.uid()) on conflict(class_id,lesson_date,student_id)
  do update set excluded=excluded.excluded,reason=excluded.reason,updated_by=excluded.updated_by,updated_at=clock_timestamp();
 end loop;
 insert into public.staff_live_signals(key,topic,entity_id,class_id,record_date)
 values('record:'||p_class_id||':'||p_date,'record',p_class_id,p_class_id,p_date)
 on conflict(key) do update set changed_at=clock_timestamp();
 return public.staff_class_edit_snapshot(p_class_id,p_date);
end $$;
revoke all on function public.staff_set_class_lesson_participants(uuid,date,jsonb,text) from public,anon;
grant execute on function public.staff_set_class_lesson_participants(uuid,date,jsonb,text) to authenticated;

create or replace function public.staff_patch_class_record_with_roster(p_class_id uuid,p_date date,p_changes jsonb,p_expected_state text,p_mode text,p_roster_version text)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null or not coalesce(public.is_staff(),false) or
 (public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid())) then raise exception '담당 클래스만 수정할 수 있습니다.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_class_id::text||':'||p_date::text,0));
 if p_roster_version is distinct from public.internal_class_participation_version(p_class_id,p_date) then raise exception '수업 대상이 변경됐습니다. 최신 명단을 확인한 뒤 저장해 주세요.'; end if;
 return public.staff_patch_class_record(p_class_id,p_date,p_changes,p_expected_state,p_mode);
end $$;
revoke all on function public.staff_patch_class_record_with_roster(uuid,date,jsonb,text,text,text) from public,anon;
grant execute on function public.staff_patch_class_record_with_roster(uuid,date,jsonb,text,text,text) to authenticated;


-- A stale preview must never send a lesson excluded since it was opened.
create or replace function public.staff_claim_learning_alimtalk_current(p_student_id uuid,p_report_type text,p_period_start date,p_period_end date,p_lesson_summary text,p_attendance_summary text,p_learning_summary text,p_source_version text)
returns table(id uuid,recipient_phone text,guardian_name text,student_name text,template_variables jsonb)
language plpgsql security definer set search_path=public as $$
declare current_lessons jsonb; d date;
begin
 if not public.can_send_alimtalk() then raise exception '관리자만 알림톡을 발송할 수 있습니다.'; end if;
 if p_period_start is null or p_period_end is null or p_period_end<p_period_start or p_period_end-p_period_start>6 then raise exception '발송 기간을 확인해 주세요.'; end if;
 for d in select generate_series(p_period_start,p_period_end,interval '1 day')::date loop
  perform pg_advisory_xact_lock(hashtextextended('alimtalk-source:'||p_student_id||':'||d,0));
 end loop;
 select lessons into current_lessons from public.internal_alimtalk_report_sources(array[p_student_id],p_period_start,p_period_end);
 if coalesce(jsonb_array_length(current_lessons),0)=0 then raise exception '발송할 수업 기록이 없습니다. 대상을 새로고침해 주세요.'; end if;
 if p_source_version is distinct from md5(current_lessons::text) then raise exception '수업 기록 또는 수업 대상이 변경됐습니다. 대상을 새로고침하고 미리보기를 확인해 주세요.'; end if;
 return query select * from public.staff_claim_learning_alimtalk(p_student_id,p_report_type,p_period_start,p_period_end,p_lesson_summary,p_attendance_summary,p_learning_summary);
end $$;
revoke all on function public.staff_claim_learning_alimtalk_current(uuid,text,date,date,text,text,text,text) from public,anon;
grant execute on function public.staff_claim_learning_alimtalk_current(uuid,text,date,date,text,text,text,text) to authenticated;
-- Direct family attendance reads must use the same visibility rule as report RPCs.
create or replace function public.family_can_read_class_attendance(p_lesson_id uuid,p_student_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
 select auth.uid() is not null and (
  exists(select 1 from public.students s where s.id=p_student_id and s.profile_id=auth.uid())
  or exists(select 1 from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id where sg.student_id=p_student_id and g.profile_id=auth.uid())
 ) and exists(select 1 from public.lessons l where l.id=p_lesson_id and not public.internal_class_student_excluded(p_student_id,l.class_id,l.lesson_date))
$$;
revoke all on function public.family_can_read_class_attendance(uuid,uuid) from public,anon;
grant execute on function public.family_can_read_class_attendance(uuid,uuid) to authenticated;
create policy attendance_participation_visibility on public.attendance as restrictive for select to authenticated
using(public.is_staff() or public.family_can_read_class_attendance(lesson_id,student_id));


-- Participation-aware: staff_monthly_lesson_coverage
CREATE OR REPLACE FUNCTION public.staff_monthly_lesson_coverage(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m date:=date_trunc('month',p_month)::date; last_day date:=(date_trunc('month',p_month)+interval '1 month - 1 day')::date;
 today date:=(now() at time zone 'Asia/Seoul')::date; role_name text:=public.current_user_role()::text; result jsonb;
begin
 if auth.uid() is null or not coalesce(public.is_staff(),false) or role_name='assistant' then raise exception '월별 수업 조회 권한이 없습니다.'; end if;
 if m is null or m<date '2000-01-01' or m>date '2100-12-01' then raise exception '조회할 월을 확인해 주세요.'; end if;
 with class_info as materialized (
  select c.*,coalesce(nullif(s.main_subject,''),nullif(s.name,''),c.subject) main_subject from classes c left join academy_subjects s on s.id=c.subject_id
 ), pairs as materialized (
  select distinct e.student_id,c.main_subject subject from enrollments e join class_info c on c.id=e.class_id
  where c.main_subject in ('국어','영어') and e.started_on<=last_day and (e.ended_on is null or e.ended_on>=m)
   and (e.status='active' or e.ended_on is not null)
   and (role_name='admin' or exists(select 1 from class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid()))
  union
  select distinct a.student_id,c.main_subject from public.internal_participating_attendance a join lessons l on l.id=a.lesson_id join class_info c on c.id=l.class_id
  where c.main_subject in ('국어','영어') and l.lesson_date between m and last_day
   and (role_name='admin' or exists(select 1 from class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid()))
  union
  select distinct ss.student_id,coalesce(nullif(s.main_subject,''),s.name) from teacher_special_lessons l join teacher_special_lesson_students ss on ss.session_id=l.id join academy_subjects s on s.id=l.subject_id
  where coalesce(nullif(s.main_subject,''),s.name) in ('국어','영어') and l.lesson_date between m and last_day
   and (role_name='admin' or l.teacher_profile_id=auth.uid())

  union
  select cm.student_id,c.main_subject from class_makeup_attendees cm join class_info c on c.id=cm.class_id
  where c.main_subject in ('국어','영어') and cm.attendance_date between m and last_day
   and (role_name='admin' or exists(select 1 from class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid()))
  union
  select a.student_id,c.main_subject from makeup_sessions ms join public.internal_participating_attendance a on a.id=ms.attendance_id join lessons l on l.id=a.lesson_id join class_info c on c.id=l.class_id
  where c.main_subject in ('국어','영어') and (ms.scheduled_at at time zone 'Asia/Seoul')::date between m and last_day
   and (role_name='admin' or ms.teacher_profile_id=auth.uid() or exists(select 1 from class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid()))
  union
  select ms.student_id,coalesce(nullif(s.main_subject,''),s.name) from source_makeup_sessions ms join teacher_special_lessons l on l.id=ms.source_id and ms.source_type='special' join academy_subjects s on s.id=l.subject_id
  where coalesce(nullif(s.main_subject,''),s.name) in ('국어','영어') and (ms.scheduled_at at time zone 'Asia/Seoul')::date between m and last_day
   and (role_name='admin' or ms.teacher_profile_id=auth.uid() or l.teacher_profile_id=auth.uid())
  union
  select t.student_id,t.subject from student_monthly_lesson_targets t where t.month=m and role_name='admin'
 ), days as (select generate_series(m::timestamp,last_day::timestamp,interval '1 day')::date d), planned as (
  select p.student_id,c.id class_id,p.subject,d.d class_date,cs.start_time start_time,cs.end_time end_time,'정규'::text kind
  from pairs p join enrollments e on e.student_id=p.student_id join class_info c on c.id=e.class_id and c.main_subject=p.subject and c.active
  join class_schedules cs on cs.class_id=c.id join days d on cs.weekday=extract(isodow from d.d)
  where (e.status='active' or e.ended_on is not null) and e.started_on<=d.d and (e.ended_on is null or e.ended_on>=d.d)
   and (cs.valid_from is null or cs.valid_from<=d.d) and (cs.valid_until is null or cs.valid_until>=d.d)
   and public.student_uses_class_schedule(p.student_id,cs.id)
   and not exists(select 1 from schedule_exceptions x where x.class_id=c.id and x.original_date=d.d and x.kind in ('cancelled','changed','makeup'))
  union all
  select p.student_id,c.id,p.subject,x.replacement_date,coalesce(x.start_time,cs.start_time),coalesce(x.end_time,cs.end_time),case when x.kind='makeup' then '보강' else '정규' end
  from pairs p join enrollments e on e.student_id=p.student_id join class_info c on c.id=e.class_id and c.main_subject=p.subject and c.active
  join schedule_exceptions x on x.class_id=c.id
  join lateral(select s.* from class_schedules s where s.class_id=c.id and s.weekday=extract(isodow from x.original_date)
   and (s.valid_from is null or s.valid_from<=x.original_date) and (s.valid_until is null or s.valid_until>=x.original_date)
   and public.student_uses_class_schedule(p.student_id,s.id) order by s.start_time limit 1) cs on true
  where x.kind in ('changed','makeup') and x.replacement_date between m and last_day
   and (e.status='active' or e.ended_on is not null) and e.started_on<=x.original_date and (e.ended_on is null or e.ended_on>=x.replacement_date)
  union all
  select p.student_id,c.id,p.subject,cm.attendance_date,cs.start_time,cs.end_time,'보강'
  from pairs p join class_makeup_attendees cm on cm.student_id=p.student_id join class_info c on c.id=cm.class_id and c.main_subject=p.subject
  left join lateral(select * from class_schedules s where s.class_id=c.id order by (s.weekday=extract(isodow from cm.attendance_date)) desc,s.start_time limit 1) cs on true
  where cm.attendance_date between m and last_day
  union all
  select p.student_id,c.id,p.subject,r.lesson_date,cs.start_time,cs.end_time,'정규'
  from pairs p join class_lesson_roster_overrides r on r.student_id=p.student_id join class_info c on c.id=r.class_id and c.main_subject=p.subject
  left join lateral(select * from class_schedules s where s.class_id=c.id and s.weekday=extract(isodow from r.lesson_date) order by s.start_time limit 1) cs on true
  where r.lesson_date between m and last_day
 ), class_days as (
  select student_id,class_id,subject,class_date,min(start_time) start_time,max(end_time) end_time,
   case when bool_or(kind='보강') then '보강' else '정규' end kind from planned group by 1,2,3,4
  union
  select p.student_id,c.id,p.subject,l.lesson_date,null::time,null::time,'정규'
  from pairs p join public.internal_participating_attendance a on a.student_id=p.student_id join lessons l on l.id=a.lesson_id join class_info c on c.id=l.class_id and c.main_subject=p.subject
  where l.lesson_date between m and last_day and not exists(select 1 from planned q where q.student_id=p.student_id and q.class_id=c.id and q.class_date=l.lesson_date)
 ), regular_events as (
  select 'regular:'||q.class_id||':'||q.class_date id,q.student_id,q.subject,q.class_date,
   coalesce(l.starts_at,(q.class_date+q.start_time) at time zone 'Asia/Seoul') starts_at,c.name title,q.kind,
   case when l.status='cancelled' then 'cancelled' when a.status in ('present','late') and q.class_date<=today then 'attended'
    when a.status in ('absent','excused') then 'absent'
    when coalesce(l.starts_at,(q.class_date+q.start_time) at time zone 'Asia/Seoul')>now() then 'planned' else 'unrecorded' end state
  from class_days q join class_info c on c.id=q.class_id
  left join lessons l on l.id=public.internal_student_class_lesson_id(q.student_id,q.class_id,q.class_date)
  left join public.internal_participating_attendance a on a.lesson_id=l.id and a.student_id=q.student_id
  where not public.internal_class_student_excluded(q.student_id,q.class_id,q.class_date)
 ), special_events as (
  select 'special:'||l.id id,p.student_id,p.subject,l.lesson_date class_date,(l.lesson_date+l.starts_at) at time zone 'Asia/Seoul' starts_at,
   coalesce(s.name,p.subject) title,case when public.internal_special_student_kind(l.id,p.student_id)='makeup' then '보강' else '추가' end kind,
   case when l.status='cancelled' then 'cancelled' when ss.attendance_status in ('present','late') and l.lesson_date<=today then 'attended'
    when ss.attendance_status in ('absent','excused') then 'absent' when (l.lesson_date+l.starts_at) at time zone 'Asia/Seoul'>now() then 'planned' else 'unrecorded' end state
  from pairs p join teacher_special_lesson_students ss on ss.student_id=p.student_id join teacher_special_lessons l on l.id=ss.session_id
  join academy_subjects s on s.id=l.subject_id and coalesce(nullif(s.main_subject,''),s.name)=p.subject
  where l.lesson_date between m and last_day
 ), legacy_events as (
  select 'makeup:'||ms.id id,p.student_id,p.subject,(ms.scheduled_at at time zone 'Asia/Seoul')::date class_date,ms.scheduled_at starts_at,c.name title,'보강'::text kind,
   case when ms.status='cancelled' then 'cancelled' when ms.status='completed' and ms.scheduled_at<=now() then 'attended' when ms.scheduled_at>now() then 'planned' else 'unrecorded' end state
  from pairs p join public.internal_participating_attendance a on a.student_id=p.student_id join lessons l on l.id=a.lesson_id join class_info c on c.id=l.class_id and c.main_subject=p.subject join makeup_sessions ms on ms.attendance_id=a.id
  where (ms.scheduled_at at time zone 'Asia/Seoul')::date between m and last_day
   and not exists(select 1 from teacher_special_lesson_students ss where ss.student_id=p.student_id and ss.makeup_source='regular' and ss.makeup_source_id=a.id)
  union all
  select 'source-makeup:'||ms.id,p.student_id,p.subject,(ms.scheduled_at at time zone 'Asia/Seoul')::date,ms.scheduled_at,coalesce(s.name,p.subject),'보강',
   case when ms.status='cancelled' then 'cancelled' when ms.status='completed' and ms.scheduled_at<=now() then 'attended' when ms.scheduled_at>now() then 'planned' else 'unrecorded' end
  from pairs p join source_makeup_sessions ms on ms.student_id=p.student_id and ms.source_type='special'
  join teacher_special_lessons l on l.id=ms.source_id join academy_subjects s on s.id=l.subject_id and coalesce(nullif(s.main_subject,''),s.name)=p.subject
  where (ms.scheduled_at at time zone 'Asia/Seoul')::date between m and last_day
   and not exists(select 1 from teacher_special_lesson_students ss where ss.student_id=p.student_id and ss.makeup_source='special' and ss.makeup_source_id=ms.source_id)
 ), events as materialized (select * from regular_events union all select * from special_events union all select * from legacy_events), rows as (
 select p.student_id,s.name,s.school,s.grade,p.subject,coalesce(t.target,case when p.subject='국어' then 8 else 12 end) target,t.version,
  count(*) filter(where ev.state='attended')::int attended,count(*) filter(where ev.state='planned')::int planned,
  count(*) filter(where ev.state='unrecorded')::int unrecorded,count(*) filter(where ev.state='absent')::int absent,
  coalesce(jsonb_agg(jsonb_build_object('id',ev.id,'date',ev.class_date,'time',to_char(ev.starts_at at time zone 'Asia/Seoul','HH24:MI'),'title',ev.title,'kind',ev.kind,'state',ev.state) order by ev.class_date,ev.starts_at,ev.id) filter(where ev.id is not null),'[]'::jsonb) events
 from pairs p join students s on s.id=p.student_id left join student_monthly_lesson_targets t on t.student_id=p.student_id and t.subject=p.subject and t.month=m
 left join events ev on ev.student_id=p.student_id and ev.subject=p.subject group by p.student_id,s.name,s.school,s.grade,p.subject,t.target,t.version
 )
 select jsonb_build_object('month',m,'today',today,'isAdmin',role_name='admin','items',coalesce(jsonb_agg(jsonb_build_object(
 'studentId',student_id,'name',name,'school',school,'grade',grade,'subject',subject,'target',target,'version',version,
 'enrollmentEnded',exists(select 1 from enrollments e join class_info c on c.id=e.class_id
   where e.student_id=rows.student_id and c.main_subject=rows.subject
    and e.ended_on<least(last_day,greatest(m,today)))
  and not exists(select 1 from enrollments e join class_info c on c.id=e.class_id
   where e.student_id=rows.student_id and c.main_subject=rows.subject
    and (e.status='active' or e.ended_on is not null) and e.started_on<=last_day
    and (e.ended_on is null or e.ended_on>=least(last_day,greatest(m,today)))),
 'attended',attended,'planned',planned,'unrecorded',unrecorded,'absent',absent,'events',events) order by name,subject),'[]'::jsonb)) into result from rows;
 return result;
end $function$
;

-- Participation-aware: staff_dashboard_live
CREATE OR REPLACE FUNCTION public.staff_dashboard_live()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with today as (
    select (now() at time zone 'Asia/Seoul')::date as day,
           extract(isodow from now() at time zone 'Asia/Seoul')::smallint as weekday
  ), attendance_totals as (
    select
      count(*) filter (where a.status = 'present') as present_count,
      count(*) filter (where a.status = 'late') as late_count,
      count(*) filter (where a.status = 'absent') as absent_count,
      count(*) as checked_count,
      count(*) filter (where a.makeup_required) as makeup_count
    from public.internal_participating_attendance a
    join public.lessons l on l.id = a.lesson_id
    join today t on t.day = l.lesson_date
  )
  select case when public.is_staff() then jsonb_build_object(
    'todayClasses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', cs.id,
        'time', cs.start_time,
        'name', c.name,
        'room', c.room,
        'color', c.color,
        'teachers', coalesce((select string_agg(p.display_name, ' · ' order by p.display_name) from public.class_teachers ct join public.profiles p on p.id = ct.profile_id where ct.class_id = c.id), '담당 미배정'),
        'enrolled', (select count(*) from public.enrollments e where e.class_id = c.id and e.status = 'active'),
        'present', (select count(*) from public.lessons l join public.internal_participating_attendance a on a.lesson_id = l.id where l.class_id = c.id and l.lesson_date = t.day and a.status = 'present')
      ) order by cs.start_time)
      from public.class_schedules cs
      join public.classes c on c.id = cs.class_id
      cross join today t
      where cs.weekday = t.weekday and c.active
        and (cs.valid_from is null or cs.valid_from <= t.day)
        and (cs.valid_until is null or cs.valid_until >= t.day)
    ), '[]'::jsonb),
    'attendance', (select jsonb_build_object('present', present_count, 'late', late_count, 'absent', absent_count, 'checked', checked_count, 'makeup', makeup_count) from attendance_totals),
    'weekAttendance', coalesce((
      select jsonb_agg(jsonb_build_object('weekday', daily.weekday, 'present', daily.present, 'late', daily.late, 'absent', daily.absent, 'checked', daily.checked) order by daily.weekday)
      from (
        select extract(isodow from days.day)::smallint as weekday,
               count(a.id) filter (where a.status = 'present') as present,
               count(a.id) filter (where a.status = 'late') as late,
               count(a.id) filter (where a.status = 'absent') as absent,
               count(a.id) as checked
        from today t
        cross join lateral generate_series(date_trunc('week', t.day::timestamp), date_trunc('week', t.day::timestamp) + interval '4 days', interval '1 day') days(day)
        left join public.lessons l on l.lesson_date = days.day::date
        left join public.internal_participating_attendance a on a.lesson_id = l.id
        group by days.day
      ) daily
    ), '[]'::jsonb)
  ) else null end
$function$
;

-- Participation-aware: staff_attendance_board
CREATE OR REPLACE FUNCTION public.staff_attendance_board(p_date date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when public.is_staff() then coalesce((
    select jsonb_agg(jsonb_build_object(
      'scheduleId', cs.id,
      'classId', c.id,
      'className', c.name,
      'subject', c.subject,
      'room', c.room,
      'color', c.color,
      'startTime', cs.start_time,
      'endTime', cs.end_time,
      'students', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', s.id,
          'name', s.name,
          'status', a.status,
          'note', a.note,
          'makeupRequired', coalesce(a.makeup_required, false)
        ) order by s.name)
        from public.enrollments e
        join public.students s on s.id = e.student_id
        left join public.lessons l on l.class_id = c.id and l.lesson_date = p_date and l.starts_at = ((p_date + cs.start_time) at time zone 'Asia/Seoul')
        left join public.internal_participating_attendance a on a.lesson_id = l.id and a.student_id = s.id
        where not public.internal_class_student_excluded(s.id,c.id,p_date) and e.class_id = c.id and e.status = 'active'
          and e.started_on <= p_date and (e.ended_on is null or e.ended_on >= p_date)
      ), '[]'::jsonb)
    ) order by cs.start_time)
    from public.class_schedules cs
    join public.classes c on c.id = cs.class_id
    where c.active
      and cs.weekday = extract(isodow from p_date)::smallint
      and (cs.valid_from is null or cs.valid_from <= p_date)
      and (cs.valid_until is null or cs.valid_until >= p_date)
      and not exists (
        select 1 from public.schedule_exceptions se
        where se.class_id = c.id and se.original_date = p_date and se.kind = 'cancelled'
      )
  ), '[]'::jsonb) else null end
$function$
;

-- Participation-aware: makeup_board
CREATE OR REPLACE FUNCTION public.makeup_board()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object(
    'isStaff', public.is_staff(),
    'teachers', case when public.is_staff() then coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.display_name) order by p.display_name) from public.profiles p where p.role in ('admin', 'teacher', 'sub_admin')), '[]'::jsonb) else '[]'::jsonb end,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'attendanceId', a.id,
        'studentId', s.id,
        'studentName', s.name,
        'className', c.name,
        'missedDate', l.lesson_date,
        'attendanceNote', a.note,
        'sessionId', ms.id,
        'teacherId', ms.teacher_profile_id,
        'teacherName', tp.display_name,
        'scheduledAt', ms.scheduled_at,
        'endsAt', ms.ends_at,
        'room', ms.room,
        'status', ms.status,
        'note', ms.note
      ) order by coalesce(ms.scheduled_at, l.starts_at), s.name)
      from public.internal_participating_attendance a
      join public.lessons l on l.id = a.lesson_id
      join public.classes c on c.id = l.class_id
      join public.students s on s.id = a.student_id
      left join public.makeup_sessions ms on ms.attendance_id = a.id
      left join public.profiles tp on tp.id = ms.teacher_profile_id
      where (
        public.is_staff() and (a.makeup_required or ms.id is not null)
      ) or (
        not public.is_staff() and ms.id is not null and ms.status <> 'cancelled' and (
          s.profile_id = auth.uid() or exists (
            select 1 from public.student_guardians sg join public.guardians g on g.id = sg.guardian_id
            where sg.student_id = s.id and g.profile_id = auth.uid()
          )
        )
      )
    ), '[]'::jsonb)
  )
$function$
;

-- Participation-aware: staff_student_attendance_makeup_history
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
        from public.internal_participating_attendance a
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
        join public.internal_participating_attendance a on a.id = ms.attendance_id
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
$function$
;

-- Participation-aware: internal_student_has_class_record
CREATE OR REPLACE FUNCTION public.internal_student_has_class_record(p_student uuid, p_class uuid, p_date date)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
 select exists(select 1 from lessons l where l.class_id=p_class and l.lesson_date=p_date and (
 exists(select 1 from public.internal_participating_attendance a where a.lesson_id=l.id and a.student_id=p_student)
 or exists(select 1 from public.internal_participating_homework h where h.lesson_id=l.id and h.student_id=p_student)
 or exists(select 1 from public.internal_participating_exams e where e.lesson_id=l.id and e.student_id=p_student)))
$function$
;

-- Participation-aware: staff_student_detail_hub
CREATE OR REPLACE FUNCTION public.staff_student_detail_hub(p_student_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 학생 통합 기록을 확인할 수 있습니다.'; end if;
  if not exists (select 1 from public.students where id = p_student_id) then raise exception '학생을 찾을 수 없습니다.'; end if;
  select jsonb_build_object(
    'summary', jsonb_build_object(
      'attendanceTotal', (select count(*) from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=p_student_id and l.lesson_date>=current_date-90),
      'present', (select count(*) from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=p_student_id and l.lesson_date>=current_date-90 and a.status='present'),
      'late', (select count(*) from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=p_student_id and l.lesson_date>=current_date-90 and a.status='late'),
      'absent', (select count(*) from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=p_student_id and l.lesson_date>=current_date-90 and a.status='absent'),
      'assignmentOpen', (select count(*) from public.assignments ass join public.enrollments e on e.class_id=ass.class_id and e.student_id=p_student_id and e.status='active' left join public.assignment_submissions sub on sub.assignment_id=ass.id and sub.student_id=p_student_id where coalesce(sub.status,'pending'::public.assignment_submission_status)<>'reviewed'),
      'upcomingMakeups', (select count(*) from public.makeup_sessions ms join public.internal_participating_attendance a on a.id=ms.attendance_id where a.student_id=p_student_id and ms.status='scheduled' and ms.scheduled_at>=now()),
      'lastConsultedAt', (select max(consulted_at) from public.consultations where student_id=p_student_id)
    ),
    'classes', coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'name',c.name,'subject',c.subject,'room',c.room,'status',e.status,'startedOn',e.started_on,'teachers',coalesce((select string_agg(p.display_name,' · ' order by p.display_name) from public.class_teachers ct join public.profiles p on p.id=ct.profile_id where ct.class_id=c.id),'')) order by (e.status='active') desc,e.started_on desc) from public.enrollments e join public.classes c on c.id=e.class_id where e.student_id=p_student_id),'[]'::jsonb),
    'guardians', coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'name',g.name,'phone',g.phone,'relationship',sg.relationship,'isPrimary',sg.is_primary) order by sg.is_primary desc,g.name) from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id where sg.student_id=p_student_id),'[]'::jsonb),
    'attendance', coalesce((select jsonb_agg(row_data order by lesson_date desc) from (select jsonb_build_object('id',a.id,'lessonDate',l.lesson_date,'className',c.name,'status',a.status,'note',a.note) row_data,l.lesson_date from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id join public.classes c on c.id=l.class_id where a.student_id=p_student_id order by l.lesson_date desc limit 30) recent),'[]'::jsonb),
    'makeups', coalesce((select jsonb_agg(jsonb_build_object('id',ms.id,'className',c.name,'missedDate',l.lesson_date,'scheduledAt',ms.scheduled_at,'endsAt',ms.ends_at,'room',ms.room,'status',ms.status,'teacherName',p.display_name,'note',ms.note) order by ms.scheduled_at desc) from public.makeup_sessions ms join public.internal_participating_attendance a on a.id=ms.attendance_id join public.lessons l on l.id=a.lesson_id join public.classes c on c.id=l.class_id join public.profiles p on p.id=ms.teacher_profile_id where a.student_id=p_student_id),'[]'::jsonb),
    'assignments', coalesce((select jsonb_agg(row_data order by due_at desc) from (select jsonb_build_object('id',ass.id,'title',ass.title,'className',c.name,'dueAt',ass.due_at,'status',coalesce(sub.status,'pending'::public.assignment_submission_status),'feedback',sub.feedback) row_data,ass.due_at from public.assignments ass join public.classes c on c.id=ass.class_id left join public.assignment_submissions sub on sub.assignment_id=ass.id and sub.student_id=p_student_id where exists (select 1 from public.enrollments e where e.class_id=ass.class_id and e.student_id=p_student_id) order by ass.due_at desc limit 20) recent),'[]'::jsonb),
    'consultations', coalesce((select jsonb_agg(row_data order by consulted_at desc) from (select jsonb_build_object('id',con.id,'consultedAt',con.consulted_at,'type',con.consultation_type,'consultantName',coalesce(p.display_name,t.name,'담당 선생님'),'internalNote',con.internal_note,'nextContactOn',con.next_contact_on) row_data,con.consulted_at from public.consultations con left join public.profiles p on p.id=con.consultant_profile_id left join public.teachers t on t.id=con.teacher_id where con.student_id=p_student_id order by con.consulted_at desc limit 20) recent),'[]'::jsonb)
  ) into result;
  return result;
end
$function$
;

-- Participation-aware: admin_operations_analytics
CREATE OR REPLACE FUNCTION public.admin_operations_analytics(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
if public.current_user_role()<>'admin' then raise exception '관리자만 운영 통계를 확인할 수 있습니다.';end if;
if p_from>p_to or p_to-p_from>366 then raise exception '조회 기간은 1년 이내로 선택해 주세요.';end if;
select jsonb_build_object(
'students',jsonb_build_object('active',(select count(*) from public.students where status in ('active','재원')),'paused',(select count(*) from public.students where status in ('paused','휴원')),'completed',(select count(*) from public.students where status in ('completed','퇴원')),'new',(select count(*) from public.students where created_at::date between p_from and p_to),'pausedInPeriod',(select count(*) from public.student_status_history where new_status='paused' and effective_on between p_from and p_to),'completedInPeriod',(select count(*) from public.student_status_history where new_status='completed' and effective_on between p_from and p_to)),
'billing',jsonb_build_object('charged',coalesce((select sum(base_amount-discount_amount+additional_amount) from public.tuition_charges where billing_month between date_trunc('month',p_from)::date and date_trunc('month',p_to)::date),0),'paid',coalesce((select sum(tp.amount) from public.tuition_payments tp join public.tuition_charges tc on tc.id=tp.charge_id where tp.paid_at::date between p_from and p_to),0),'outstanding',coalesce((select sum(greatest(tc.base_amount-tc.discount_amount+tc.additional_amount-coalesce((select sum(tp.amount) from public.tuition_payments tp where tp.charge_id=tc.id),0),0)) from public.tuition_charges tc where tc.billing_month between date_trunc('month',p_from)::date and date_trunc('month',p_to)::date and tc.status<>'waived'),0)),
'attendance',jsonb_build_object('total',(select count(*) from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id where l.lesson_date between p_from and p_to),'present',(select count(*) from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id where l.lesson_date between p_from and p_to and a.status='present'),'late',(select count(*) from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id where l.lesson_date between p_from and p_to and a.status='late'),'absent',(select count(*) from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id where l.lesson_date between p_from and p_to and a.status='absent'),'makeupNeeded',(select count(*) from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id where l.lesson_date between p_from and p_to and a.makeup_required),'makeupCompleted',(select count(*) from public.makeup_sessions ms where ms.status='completed' and ms.scheduled_at::date between p_from and p_to)),
'operations',jsonb_build_object('activeClasses',(select count(*) from public.classes where active),'teachers',(select count(*) from public.profiles where role in ('admin','teacher','sub_admin') and is_active),'correctionStudents',(select count(distinct student_id) from public.correction_assignments where valid_from<=p_to and (valid_until is null or valid_until>=p_from)),'vehicleStudents',(select count(distinct vb.student_id) from public.vehicle_boardings vb join public.vehicle_runs vr on vr.id=vb.run_id where vr.active)),
'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'subject',c.subject,'enrolled',(select count(*) from public.enrollments e where e.class_id=c.id and e.status='active'),'teachers',(select count(*) from public.class_teachers ct where ct.class_id=c.id),'attendanceRate',coalesce((select round(100.0*count(*)filter(where a.status='present')/nullif(count(*),0)) from public.lessons l join public.internal_participating_attendance a on a.lesson_id=l.id where l.class_id=c.id and l.lesson_date between p_from and p_to),0)) order by c.name) from public.classes c where c.active),'[]'::jsonb),
'teachers',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name,'classes',(select count(*) from public.class_teachers ct where ct.profile_id=p.id),'correctionStudents',(select count(distinct ca.student_id) from public.correction_assignments ca where ca.teacher_profile_id=p.id and ca.valid_from<=p_to and (ca.valid_until is null or ca.valid_until>=p_from)),'consultations',(select count(*) from public.consultations c where c.consultant_profile_id=p.id and c.consulted_at::date between p_from and p_to)) order by p.display_name) from public.profiles p where p.role in ('admin','teacher','sub_admin') and p.is_active),'[]'::jsonb),
'monthly',coalesce((select jsonb_agg(jsonb_build_object('month',m.month_start,'newStudents',(select count(*) from public.students s where s.created_at::date>=m.month_start and s.created_at::date<(m.month_start+interval '1 month')::date),'charged',coalesce((select sum(base_amount-discount_amount+additional_amount) from public.tuition_charges tc where tc.billing_month=m.month_start),0),'paid',coalesce((select sum(tp.amount) from public.tuition_payments tp where tp.paid_at::date>=m.month_start and tp.paid_at::date<(m.month_start+interval '1 month')::date),0)) order by m.month_start) from (select generate_series(date_trunc('month',p_from),date_trunc('month',p_to),interval '1 month')::date month_start)m),'[]'::jsonb)
) into result;return result;end $function$
;

-- Participation-aware: family_summary_snapshot
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
      'exams',coalesce((select jsonb_agg(jsonb_build_object('id',er.id,'examType',coalesce(er.exam_type,''),'examTitle',coalesce(er.exam_title,''),'score',er.score,'maxScore',coalesce(er.max_score,100),'percent',case when er.score is null or coalesce(er.max_score,0)<=0 then null else round(er.score/er.max_score*100,1) end,'evaluation',coalesce(er.evaluation,''),'feedback',coalesce(er.feedback,'')) order by er.created_at,er.id) from public.internal_participating_exams er where er.lesson_id=l.id and er.student_id=selected_id and er.id=public.internal_class_current_exam_id(l.id,selected_id) and (er.score is not null or nullif(trim(concat_ws(' ',er.exam_type,er.exam_title,er.evaluation,er.feedback)),'') is not null)),'[]'::jsonb)
    ) item,l.lesson_date,l.starts_at::text starts_at
    from public.lessons l join public.classes c on c.id=l.class_id 
    left join public.profiles tp on tp.id=l.teacher_profile_id left join public.internal_participating_attendance a on a.lesson_id=l.id and a.student_id=selected_id left join public.internal_participating_homework hr on hr.lesson_id=l.id and hr.student_id=selected_id
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
end $function$
;

-- Participation-aware: staff_class_lesson_history
CREATE OR REPLACE FUNCTION public.staff_class_lesson_history(p_class_id uuid, p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role public.user_role;
  v_result jsonb;
begin
  v_role := public.current_user_role();
  if v_role not in ('admin', 'teacher', 'sub_admin') then
    raise exception '교직원만 수업일지를 확인할 수 있습니다.';
  end if;

  if v_role in ('teacher','sub_admin') and not exists (
    select 1 from public.class_teachers ct
    where ct.class_id = p_class_id and ct.profile_id = auth.uid()
  ) then
    raise exception '담당 클래스의 수업일지만 확인할 수 있습니다.';
  end if;

  select coalesce(jsonb_agg(history.row_data order by history.lesson_date desc, history.starts_at desc), '[]'::jsonb)
  into v_result
  from (
    select
      l.lesson_date,
      l.starts_at,
      jsonb_build_object(
        'id', l.id,
        'lessonDate', l.lesson_date,
        'startsAt', l.starts_at,
        'examContent', l.exam_content,
        'lessonContent', l.lesson_content,
        'homeworkContent', l.homework_content,
        'teacherName', coalesce(p.display_name, '담당 선생님'),
        'present', (select count(*) from public.internal_participating_attendance a where a.lesson_id = l.id and a.status = 'present'),
        'late', (select count(*) from public.internal_participating_attendance a where a.lesson_id = l.id and a.status = 'late'),
        'absent', (select count(*) from public.internal_participating_attendance a where a.lesson_id = l.id and a.status = 'absent'),
        'excused', (select count(*) from public.internal_participating_attendance a where a.lesson_id = l.id and a.status = 'excused'),
        'updatedAt', l.updated_at
      ) as row_data
    from public.lessons l
    left join public.profiles p on p.id = l.teacher_profile_id
    where l.class_id = p_class_id
    order by l.lesson_date desc, l.starts_at desc
    limit greatest(1, least(coalesce(p_limit, 100), 300))
  ) history;

  return v_result;
end;
$function$
;

-- Participation-aware: staff_student_exam_progress
CREATE OR REPLACE FUNCTION public.staff_student_exam_progress(p_student_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_staff() then raise exception '교직원만 성적 추이를 확인할 수 있습니다.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'lessonDate',l.lesson_date,'className',c.name,'subject',c.subject,'examType',coalesce(r.exam_type,''),'examTitle',coalesce(r.exam_title,''),'score',r.score,'maxScore',r.max_score,'percent',case when r.score is null or coalesce(r.max_score,0)<=0 then null else round(r.score/r.max_score*100,1) end,'evaluation',coalesce(r.evaluation,'')) order by l.lesson_date,r.created_at) from public.internal_participating_exams r join public.lessons l on l.id=r.lesson_id join public.classes c on c.id=l.class_id where r.student_id=p_student_id),'[]'::jsonb);
end $function$
;

-- Participation-aware: staff_class_attendance_calendar
CREATE OR REPLACE FUNCTION public.staff_class_attendance_calendar(p_class_id uuid, p_anchor_date date, p_view text DEFAULT 'week'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare first_day date; last_day date; result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 출석 캘린더를 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(
    select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()
  ) then raise exception '담당 클래스의 출석 캘린더만 확인할 수 있습니다.'; end if;

  if p_view='month' then
    first_day:=date_trunc('month',p_anchor_date)::date;
    last_day:=(date_trunc('month',p_anchor_date)+interval '1 month - 1 day')::date;
  else
    first_day:=p_anchor_date-(extract(isodow from p_anchor_date)::integer-1);
    last_day:=first_day+6;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'date',to_char(d.day::date,'YYYY-MM-DD'),
    'scheduled',exists(
      select 1 from public.class_schedules cs
      where cs.class_id=p_class_id and cs.weekday=extract(isodow from d.day::date)::smallint
        and (cs.valid_from is null or cs.valid_from<=d.day::date)
        and (cs.valid_until is null or cs.valid_until>=d.day::date)
    ),
    'students',coalesce((
      select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'status',a.status) order by s.name)
      from public.lessons l
      join public.internal_participating_attendance a on a.lesson_id=l.id
      join public.students s on s.id=a.student_id
      where l.class_id=p_class_id and l.lesson_date=d.day::date
        and l.id=public.internal_student_class_lesson_id(s.id,p_class_id,d.day::date)
    ),'[]'::jsonb)
  ) order by d.day),'[]'::jsonb)
  into result
  from generate_series(first_day,last_day,interval '1 day') d(day);
  return result;
end $function$
;

-- Participation-aware: family_previous_homework
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
   and exists(select 1 from public.internal_participating_attendance a where a.lesson_id=l.id and a.student_id=selected_id);
  if found then
   select coalesce(hr.assigned_homework,l.homework_content,'') into result
   from public.lessons l left join public.internal_participating_homework hr on hr.lesson_id=l.id and hr.student_id=selected_id
   where l.class_id=current_row.class_id and l.status='completed' and l.starts_at<current_row.starts_at and l.lesson_date<=current_date
    and exists(select 1 from public.internal_participating_attendance a where a.lesson_id=l.id and a.student_id=selected_id)
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
end $function$
;

-- Participation-aware: staff_class_previous_learning_template
CREATE OR REPLACE FUNCTION public.staff_class_previous_learning_template(p_class_id uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_lesson public.lessons; v_notice text; v_exam jsonb; v_homework text;
begin
  if not public.is_staff() then raise exception '교직원만 이전 수업 기록을 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers ct where ct.class_id=p_class_id and ct.profile_id=auth.uid()) then
    raise exception '담당 클래스만 확인할 수 있습니다.';
  end if;
  select * into v_lesson from public.lessons where class_id=p_class_id and lesson_date<p_date order by lesson_date desc,starts_at desc limit 1;
  if v_lesson.id is null then return null; end if;
  select content into v_notice from public.class_daily_notices where class_id=p_class_id and notice_date=v_lesson.lesson_date;
  select jsonb_build_object('examType',coalesce(er.exam_type,''),'examTitle',coalesce(er.exam_title,''),'maxScore',coalesce(er.max_score,100),'evaluation',coalesce(er.evaluation,''))
    into v_exam from public.internal_participating_exams er where er.lesson_id=v_lesson.id and (nullif(trim(er.exam_type),'') is not null or nullif(trim(er.exam_title),'') is not null) order by er.updated_at desc limit 1;
  select hr.assigned_homework into v_homework from public.internal_participating_homework hr where hr.lesson_id=v_lesson.id and nullif(trim(hr.assigned_homework),'') is not null order by hr.updated_at desc limit 1;
  return jsonb_build_object('lessonDate',to_char(v_lesson.lesson_date,'YYYY-MM-DD'),'lessonContent',coalesce(v_lesson.lesson_content,''),'notice',coalesce(v_notice,''),'exam',coalesce(v_exam,'{}'::jsonb),'assignedHomework',coalesce(v_homework,''));
end $function$
;

-- Participation-aware: family_learning_reports
CREATE OR REPLACE FUNCTION public.family_learning_reports(p_student_id uuid DEFAULT NULL::uuid, p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare viewer_role public.user_role; selected_id uuid; safe_limit integer; result jsonb;
begin
  viewer_role:=public.current_user_role();
  if viewer_role is null or viewer_role not in ('student','guardian') then raise exception '학생 또는 학부모 계정만 학습리포트를 확인할 수 있습니다.'; end if;
  if viewer_role='student' then
    select s.id into selected_id from public.students s where s.profile_id=auth.uid();
    if p_student_id is not null and p_student_id<>selected_id then raise exception '본인 학습리포트만 확인할 수 있습니다.'; end if;
  else
    if p_student_id is null then
      select s.id into selected_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() order by sg.is_primary desc,s.name limit 1;
    else
      select s.id into selected_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() and s.id=p_student_id;
      if selected_id is null then raise exception '연결된 자녀의 학습리포트만 확인할 수 있습니다.'; end if;
    end if;
  end if;
  if selected_id is null then return '[]'::jsonb; end if;
  safe_limit:=greatest(1,least(coalesce(p_limit,10),30));
  select coalesce(jsonb_agg(report_row order by lesson_date desc,starts_at desc),'[]'::jsonb) into result from (
    select jsonb_build_object(
      'lessonId',l.id,'lessonDate',to_char(l.lesson_date,'YYYY-MM-DD'),'startsAt',l.starts_at,'classId',c.id,'className',c.name,'subject',c.subject,'room',coalesce(l.room,c.room),'teacherName',coalesce(tp.display_name,'담당 선생님'),
      'lessonContent',coalesce(l.lesson_content,''),'classNotice',coalesce(n.content,''),'homeworkContent',coalesce(hr.assigned_homework,l.homework_content,''),'examContent',coalesce(l.exam_content,''),
      'attendance',case when a.id is null then null else jsonb_build_object('status',a.status,'lateMinutes',a.late_minutes,'absenceReason',coalesce(a.absence_reason,''),'note',coalesce(a.note,'')) end,
      'homeworkResult',case when hr.id is null then null else jsonb_build_object('status',coalesce(hr.inspection_status,hr.status,''),'note',coalesce(hr.inspection_note,hr.note,'')) end,
      'exams',coalesce((select jsonb_agg(jsonb_build_object('id',er.id,'examType',coalesce(er.exam_type,''),'examTitle',coalesce(er.exam_title,''),'score',er.score,'maxScore',coalesce(er.max_score,100),'percent',case when er.score is null or coalesce(er.max_score,0)<=0 then null else round(er.score/er.max_score*100,1) end,'evaluation',coalesce(er.evaluation,''),'feedback',coalesce(er.feedback,'')) order by er.created_at,er.id) from public.internal_participating_exams er where er.lesson_id=l.id and er.student_id=selected_id and er.id=public.internal_class_current_exam_id(l.id,selected_id) and (er.score is not null or nullif(trim(concat_ws(' ',er.exam_type,er.exam_title,er.evaluation,er.feedback)),'') is not null)),'[]'::jsonb)
    ) report_row,l.lesson_date,l.starts_at
    from public.lessons l join public.classes c on c.id=l.class_id 
    left join public.profiles tp on tp.id=l.teacher_profile_id left join public.internal_participating_attendance a on a.lesson_id=l.id and a.student_id=selected_id left join public.internal_participating_homework hr on hr.lesson_id=l.id and hr.student_id=selected_id
    left join public.class_daily_notices n on n.class_id=l.class_id and n.notice_date=l.lesson_date
    where l.status='completed' and not public.internal_class_student_excluded(selected_id,l.class_id,l.lesson_date) and (exists(select 1 from public.enrollments e where e.class_id=c.id and e.student_id=selected_id and e.started_on<=l.lesson_date and (e.ended_on is null or e.ended_on>=l.lesson_date)) or (l.status='completed' and a.id is not null)) and l.lesson_date<=current_date and (a.id is not null or hr.id is not null or nullif(trim(l.lesson_content),'') is not null or nullif(trim(l.homework_content),'') is not null or nullif(trim(l.exam_content),'') is not null or exists(select 1 from public.internal_participating_exams er where er.lesson_id=l.id and er.student_id=selected_id and er.id=public.internal_class_current_exam_id(l.id,selected_id) and (er.score is not null or nullif(trim(concat_ws(' ',er.exam_type,er.exam_title,er.evaluation,er.feedback)),'') is not null)))
    order by l.lesson_date desc,l.starts_at desc limit safe_limit
  ) reports;
  return result;
end $function$
;

-- Participation-aware: staff_record_worklist
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
      exists(select 1 from public.lessons l join public.internal_participating_attendance at on at.lesson_id=l.id and at.student_id=e.student_id where l.class_id=cs.class_id and l.lesson_date=d.occurrence_date and l.status='completed' and at.status::text in ('present','late','absent','excused')) completed
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
      exists(select 1 from public.lessons l join public.internal_participating_attendance at on at.lesson_id=l.id and at.student_id=e.student_id where l.class_id=x.class_id and l.lesson_date=x.replacement_date and l.status='completed' and at.status::text in ('present','late','absent','excused'))
    from public.schedule_exceptions x join public.class_schedules cs on cs.class_id=x.class_id and cs.weekday=extract(isodow from x.original_date)::smallint
    join public.classes c on c.id=x.class_id and c.active join public.enrollments e on e.class_id=c.id and e.status='active'
      and e.started_on<=x.replacement_date and (e.ended_on is null or e.ended_on>=x.replacement_date)
    join public.students s on s.id=e.student_id and s.status in ('active','재원')
    where (cs.valid_from is null or cs.valid_from<=x.original_date) and (cs.valid_until is null or cs.valid_until>=x.original_date) and public.student_attends_class_on(e.student_id,x.class_id,x.original_date) and x.kind in ('changed','makeup') and x.replacement_date between p_from and p_to
  ),
  class_makeups as (
    select distinct m.student_id,'class-makeup:'||m.class_id||':'||m.attendance_date expected_key,'보강수업',c.name,m.attendance_date,cs.start_time,
      exists(select 1 from public.lessons l join public.internal_participating_attendance at on at.lesson_id=l.id and at.student_id=m.student_id where l.class_id=m.class_id and l.lesson_date=m.attendance_date and l.status='completed' and at.status::text in ('present','late','absent','excused'))
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
      exists(select 1 from public.lessons ll join public.internal_participating_attendance a on a.lesson_id=ll.id and a.student_id=o.student_id where ll.class_id=o.class_id and ll.lesson_date=o.lesson_date and ll.status='completed' and a.status::text in ('present','late','absent','excused'))
    from public.class_lesson_roster_overrides o join public.classes c on c.id=o.class_id
    join public.students s on s.id=o.student_id and s.status in ('active','재원')
    left join public.lessons l on l.class_id=o.class_id and l.lesson_date=o.lesson_date
    left join public.class_schedules cs on cs.class_id=o.class_id and cs.weekday=extract(isodow from o.lesson_date)
    where o.lesson_date between p_from and p_to
      and not exists(select 1 from public.schedule_exceptions x where x.class_id=o.class_id and x.original_date=o.lesson_date and x.kind in ('cancelled','changed','makeup'))
  ),
  scheduled_expected_raw as (
    select * from regular_fixed union select * from regular_replacements union select * from class_makeups
    union select * from roster_additions
    union all select * from special_lessons union all select * from correction_fixed union select * from correction_changes
  ),
 scheduled_expected as (select * from scheduled_expected_raw e where case when split_part(e.expected_key,':',1) in ('regular','class-makeup') then not public.internal_class_student_excluded(e.student_id,split_part(e.expected_key,':',2)::uuid,e.occurrence_date) else true end),
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
 else exists(select 1 from public.internal_participating_attendance a where a.lesson_id=l.id and a.student_id=e.student_id and a.status::text in ('present','late','absent','excused')) end has_attendance
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
end $function$
;

-- Participation-aware: internal_alimtalk_report_sources
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
          select current_exam.* from public.internal_participating_exams current_exam
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
 join public.internal_participating_attendance a on a.lesson_id=l.id and a.student_id=any(p_student_ids)
 left join public.profiles tp on tp.id=l.teacher_profile_id
 left join public.internal_participating_homework hr on hr.lesson_id=l.id and hr.student_id=a.student_id
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
$function$
;

-- Participation-aware: staff_student_learning_history
CREATE OR REPLACE FUNCTION public.staff_student_learning_history(p_student_id uuid, p_limit integer DEFAULT 300)
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
  safe_limit := greatest(1, least(coalesce(p_limit, 300), 500));

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
        from public.internal_participating_exams er
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
    left join public.internal_participating_attendance a on a.lesson_id = l.id and a.student_id = p_student_id
    left join public.internal_participating_homework hr on hr.lesson_id = l.id and hr.student_id = p_student_id
    where e.started_on <= l.lesson_date
      and (e.ended_on is null or e.ended_on >= l.lesson_date)
      and l.lesson_date <= current_date
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
          select 1 from public.internal_participating_exams er
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

-- Participation-aware: staff_student_attendance_rates
CREATE OR REPLACE FUNCTION public.staff_student_attendance_rates(p_days integer DEFAULT 30)
 RETURNS TABLE(student_id uuid, checked_count bigint, present_count bigint, late_count bigint, absent_count bigint, attendance_rate integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select a.student_id,
    count(*) filter (where a.status in ('present','late','absent')),
    count(*) filter (where a.status = 'present'),
    count(*) filter (where a.status = 'late'),
    count(*) filter (where a.status = 'absent'),
    round(100.0 * count(*) filter (where a.status = 'present') / nullif(count(*) filter (where a.status in ('present','late','absent')), 0))::integer
  from public.internal_participating_attendance a join public.lessons l on l.id = a.lesson_id
  where public.is_staff()
    and l.lesson_date between (now() at time zone 'Asia/Seoul')::date - greatest(1, least(coalesce(p_days, 30), 365)) + 1
      and (now() at time zone 'Asia/Seoul')::date
  group by a.student_id
$function$
;

-- Participation-aware: family_completed_learning_reports
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
      left join public.internal_participating_homework hr on hr.lesson_id=l.id and hr.student_id=selected_id
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
end $function$
;

-- Participation-aware: staff_student_detail_insights
CREATE OR REPLACE FUNCTION public.staff_student_detail_insights(p_student_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_staff() then raise exception '교직원만 학생 통합 기록을 확인할 수 있습니다.'; end if;
  if not exists (select 1 from public.students where id = p_student_id) then raise exception '학생을 찾을 수 없습니다.'; end if;
  return jsonb_build_object(
    'regularAttendance', jsonb_build_object(
      'attendanceTotal', (select count(*) from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=p_student_id and l.lesson_date>=current_date-30),
      'present', (select count(*) from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=p_student_id and l.lesson_date>=current_date-30 and a.status='present'),
      'late', (select count(*) from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=p_student_id and l.lesson_date>=current_date-30 and a.status='late'),
      'absent', (select count(*) from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=p_student_id and l.lesson_date>=current_date-30 and a.status in ('absent','excused'))
    ),
    'correctionAttendance', jsonb_build_object(
      'attendanceTotal', (select count(*) from public.correction_reports r where r.student_id=p_student_id and r.correction_date>=current_date-30 and r.attendance_status<>'scheduled'),
      'present', (select count(*) from public.correction_reports r where r.student_id=p_student_id and r.correction_date>=current_date-30 and r.attendance_status='present'),
      'late', (select count(*) from public.correction_reports r where r.student_id=p_student_id and r.correction_date>=current_date-30 and r.attendance_status='late'),
      'absent', (select count(*) from public.correction_reports r where r.student_id=p_student_id and r.correction_date>=current_date-30 and r.attendance_status='absent')
    ),
    'correctionAttendanceRecords', coalesce((
      select jsonb_agg(to_jsonb(q) order by q."lessonDate" desc,q."startTime" desc)
      from (
        select r.id,r.correction_date as "lessonDate",(r.subject||' 첨삭')::text as "className",r.subject,
          r.start_time as "startTime",r.attendance_status as status,
          case when r.attendance_status='late' and r.late_minutes is not null then r.late_minutes||'분 지각'
               when r.attendance_status='absent' then coalesce(nullif(r.absence_reason,''),'결석 사유 없음')
               else null end as note
        from public.correction_reports r
        where r.student_id=p_student_id and r.attendance_status<>'scheduled'
        order by r.correction_date desc,r.start_time desc limit 30
      ) q
    ),'[]'::jsonb),
    'correctionExams', coalesce((
      select jsonb_agg(to_jsonb(q) order by q."lessonDate",q.id)
      from (
        select r.id,r.correction_date as "lessonDate",(r.subject||' 첨삭')::text as "className",r.subject,
          case when coalesce(r.exam_range,'') like '[종류]%'
            then nullif(trim(replace(split_part(r.exam_range,E'\n',1),'[종류]','')),'')
            else '첨삭 시험' end as "examType",
          coalesce(r.exam_title,'') as "examTitle",r.exam_score as score,
          coalesce(nullif(r.exam_max_score,0),100) as "maxScore",
          round(r.exam_score*100.0/coalesce(nullif(r.exam_max_score,0),100),1) as percent,
          coalesce(r.evaluation,'') as evaluation
        from public.correction_reports r
        where r.student_id=p_student_id and r.exam_score is not null
        order by r.correction_date desc,r.created_at desc limit 50
      ) q
    ),'[]'::jsonb),
    'correctionLearning', coalesce((
      select jsonb_agg(to_jsonb(q) order by q."lessonDate" desc,q.id desc)
      from (
        select r.id,r.correction_date as "lessonDate",r.subject,
          coalesce(r.homework_instruction,'') as "homeworkInstruction",
          coalesce(r.homework_status,'') as "homeworkStatus",
          coalesce(r.homework_note,'') as "homeworkNote",
          coalesce(r.correction_content,'') as "correctionContent",
          coalesce(r.assistant_feedback,'') as "assistantFeedback"
        from public.correction_reports r
        where r.student_id=p_student_id and (
          nullif(trim(r.homework_instruction),'') is not null or nullif(trim(r.homework_note),'') is not null or
          nullif(trim(r.correction_content),'') is not null or nullif(trim(r.assistant_feedback),'') is not null
        )
        order by r.correction_date desc,r.created_at desc limit 20
      ) q
    ),'[]'::jsonb)
  );
end
$function$
;

-- Participation-aware: staff_student_completed_learning_history
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
    left join public.internal_participating_homework hr on hr.lesson_id=l.id and hr.student_id=p_student_id
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
end $function$
;

-- Participation-aware: absence_makeup_board
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
      from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id join public.classes c on c.id=l.class_id join public.students st on st.id=a.student_id left join public.academy_subjects sub on sub.id=c.subject_id left join public.makeup_sessions ms on ms.attendance_id=a.id left join public.profiles tp on tp.id=ms.teacher_profile_id
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
      select jsonb_build_object('attendanceId',null,'sourceId',null,'recordKind','schedule','studentId',st.id,'studentName',st.name,'classId',c.id,'className',c.name,'subjectId',c.subject_id,'subjectName',coalesce(sub.name,c.subject,'과목 미지정'),'missedDate',null,'attendanceNote',null,'sessionId',concat('class:',m.class_id,':',m.attendance_date),'teacherId',coalesce(l.teacher_profile_id,m.created_by),'teacherName',coalesce(lp.display_name,cp.display_name),'scheduledAt',coalesce(l.starts_at,((m.attendance_date+coalesce(sched.start_time,'18:00'::time)) at time zone 'Asia/Seoul')),'endsAt',coalesce(l.ends_at,((m.attendance_date+coalesce(sched.end_time,'20:00'::time)) at time zone 'Asia/Seoul')),'room',coalesce(l.room,c.room),'status',case when l.id is not null and (exists(select 1 from public.internal_participating_attendance ca where ca.lesson_id=l.id and ca.student_id=st.id) or nullif(trim(l.lesson_content),'') is not null or nullif(trim(l.homework_content),'') is not null or nullif(trim(l.exam_content),'') is not null) then 'completed' else 'scheduled' end,'note',null,'source','class') row_data,
        coalesce(l.starts_at,((m.attendance_date+coalesce(sched.start_time,'18:00'::time)) at time zone 'Asia/Seoul')) sort_date,st.name student_name
      from public.class_makeup_attendees m join public.classes c on c.id=m.class_id join public.students st on st.id=m.student_id left join public.academy_subjects sub on sub.id=c.subject_id left join lateral (select lesson.* from public.lessons lesson where lesson.class_id=m.class_id and lesson.lesson_date=m.attendance_date order by lesson.starts_at limit 1) l on true left join lateral (select cs.start_time,cs.end_time from public.class_schedules cs where cs.class_id=m.class_id order by cs.start_time limit 1) sched on true left join public.profiles lp on lp.id=l.teacher_profile_id left join public.profiles cp on cp.id=m.created_by
      where not exists(select 1 from public.internal_participating_attendance ca where ca.lesson_id=l.id and ca.student_id=st.id and ca.status='absent') and (v_role='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid()))
      union all
      select jsonb_build_object('attendanceId',null,'sourceId',sl.id,'recordKind','schedule','studentId',st.id,'studentName',st.name,'classId',scope.class_id,'className',coalesce(scope.class_name,'개별 보강'),'subjectId',sl.subject_id,'subjectName',coalesce(sub.name,'과목 미지정'),'missedDate',null,'attendanceNote',null,'sessionId',sl.id,'teacherId',sl.teacher_profile_id,'teacherName',tp.display_name,'scheduledAt',((sl.lesson_date+sl.starts_at) at time zone 'Asia/Seoul'),'endsAt',((sl.lesson_date+sl.ends_at) at time zone 'Asia/Seoul'),'room',sl.room,'status',case when sl.status='completed' then 'completed' else 'scheduled' end,'note',sl.note,'source','individual') row_data,
        ((sl.lesson_date+sl.starts_at) at time zone 'Asia/Seoul') sort_date,st.name student_name
      from public.teacher_special_lessons sl join public.teacher_special_lesson_students ss on ss.session_id=sl.id join public.students st on st.id=ss.student_id join public.profiles tp on tp.id=sl.teacher_profile_id left join public.academy_subjects sub on sub.id=sl.subject_id left join lateral (select c.id class_id,c.name class_name from public.enrollments e join public.classes c on c.id=e.class_id where e.student_id=st.id and e.status='active' and c.active and (sl.subject_id is null or c.subject_id=sl.subject_id) order by c.name limit 1) scope on true
      where public.internal_special_student_kind(sl.id,ss.student_id)='makeup' and ss.attendance_status is distinct from 'absent' and (v_role='admin' or sl.teacher_profile_id=auth.uid() or exists(select 1 from public.class_teachers ct where ct.class_id=scope.class_id and ct.profile_id=auth.uid()))
    ) rows),'[]'::jsonb)
  ));
end $function$
;

-- Participation-aware: specialized_learning_history_range
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
        from public.internal_participating_exams er
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
    left join public.profiles tp on tp.id = l.teacher_profile_id
    left join public.internal_participating_attendance a on a.lesson_id = l.id and a.student_id = p_student_id
    left join public.internal_participating_homework hr on hr.lesson_id = l.id and hr.student_id = p_student_id
    where (a.id is not null or exists(select 1 from public.enrollments e where e.class_id=c.id and e.student_id=p_student_id and e.started_on<=l.lesson_date and (e.ended_on is null or e.ended_on>=l.lesson_date)))
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
          select 1 from public.internal_participating_exams er
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

-- Participation-aware: specialized_completed_history_range
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
    left join public.internal_participating_homework hr on hr.lesson_id=l.id and hr.student_id=p_student_id
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
end $function$
;

-- Participation-aware: family_live_dashboard
CREATE OR REPLACE FUNCTION public.family_live_dashboard(p_student_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare viewer_role public.user_role; selected_id uuid; result jsonb;
begin
  viewer_role := public.current_user_role();
  if viewer_role is null or viewer_role not in ('student','guardian') then raise exception '학생 또는 학부모 계정만 가족 대시보드를 확인할 수 있습니다.'; end if;
  if viewer_role='student' then
    select id into selected_id from public.students where profile_id=auth.uid();
    if p_student_id is not null and p_student_id<>selected_id then raise exception '본인 학생 정보만 확인할 수 있습니다.'; end if;
  else
    if p_student_id is null then select s.id into selected_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() order by sg.is_primary desc,s.name limit 1;
    else
      select s.id into selected_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() and s.id=p_student_id;
      if selected_id is null then raise exception '연결된 자녀만 확인할 수 있습니다.'; end if;
    end if;
  end if;
  select jsonb_build_object(
    'role',viewer_role,
    'children',case when viewer_role='guardian' then coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade) order by sg.is_primary desc,s.name) from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid()),'[]'::jsonb) else coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade)) from public.students s where s.id=selected_id),'[]'::jsonb) end,
    'selectedStudent',(select jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade) from public.students s where s.id=selected_id),
    'weekClasses',coalesce((select jsonb_agg(jsonb_build_object('id',cs.id,'name',c.name,'subject',c.subject,'room',c.room,'color',c.color,'weekday',cs.weekday,'startTime',cs.start_time,'endTime',cs.end_time,'teachers',coalesce((select string_agg(p.display_name,' · ' order by p.display_name) from public.class_teachers ct join public.profiles p on p.id=ct.profile_id where ct.class_id=c.id),'')) order by cs.weekday,cs.start_time) from public.enrollments e join public.classes c on c.id=e.class_id join public.class_schedules cs on cs.class_id=c.id where e.student_id=selected_id and e.status='active' and c.active and (not exists(select 1 from public.student_schedule_assignments a where a.student_id=selected_id) or exists(select 1 from public.student_schedule_assignments a where a.student_id=selected_id and a.class_schedule_id=cs.id)) and (cs.valid_from is null or cs.valid_from<=current_date) and (cs.valid_until is null or cs.valid_until>=current_date)),'[]'::jsonb),
    'upcomingClasses',coalesce((select jsonb_agg(row_data order by class_date,start_time) from (select jsonb_build_object('id',cs.id,'name',c.name,'subject',c.subject,'room',c.room,'color',c.color,'classDate',days.class_date,'startTime',cs.start_time,'teachers',coalesce((select string_agg(p.display_name,' · ' order by p.display_name) from public.class_teachers ct join public.profiles p on p.id=ct.profile_id where ct.class_id=c.id),'')) row_data,days.class_date,cs.start_time from public.enrollments e join public.classes c on c.id=e.class_id join public.class_schedules cs on cs.class_id=c.id cross join lateral (select day::date class_date from generate_series(current_date,current_date+13,interval '1 day') day) days where e.student_id=selected_id and e.status='active' and c.active and (not exists(select 1 from public.student_schedule_assignments a where a.student_id=selected_id) or exists(select 1 from public.student_schedule_assignments a where a.student_id=selected_id and a.class_schedule_id=cs.id)) and not public.internal_class_student_excluded(selected_id,c.id,days.class_date) and cs.weekday=extract(isodow from days.class_date)::smallint and (cs.valid_from is null or cs.valid_from<=days.class_date) and (cs.valid_until is null or cs.valid_until>=days.class_date) and not exists(select 1 from public.schedule_exceptions se where se.class_id=c.id and se.original_date=days.class_date and se.kind='cancelled') order by days.class_date,cs.start_time limit 6) upcoming),'[]'::jsonb),
    'attendanceSummary',jsonb_build_object('total',(select count(*) from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=selected_id and l.lesson_date>=date_trunc('month',current_date)::date),'present',(select count(*) from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=selected_id and l.lesson_date>=date_trunc('month',current_date)::date and a.status='present'),'late',(select count(*) from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=selected_id and l.lesson_date>=date_trunc('month',current_date)::date and a.status='late'),'absent',(select count(*) from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=selected_id and l.lesson_date>=date_trunc('month',current_date)::date and a.status='absent')),
    'recentAttendance',coalesce((select jsonb_agg(row_data order by lesson_date desc) from (select jsonb_build_object('id',a.id,'lessonDate',l.lesson_date,'className',c.name,'status',a.status,'note',a.note) row_data,l.lesson_date from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id join public.classes c on c.id=l.class_id where a.student_id=selected_id order by l.lesson_date desc limit 10) recent),'[]'::jsonb),
    'makeups',coalesce((select jsonb_agg(jsonb_build_object('id',ms.id,'className',c.name,'scheduledAt',ms.scheduled_at,'room',ms.room,'status',ms.status,'teacherName',p.display_name) order by ms.scheduled_at) from public.makeup_sessions ms join public.internal_participating_attendance a on a.id=ms.attendance_id join public.lessons l on l.id=a.lesson_id join public.classes c on c.id=l.class_id join public.profiles p on p.id=ms.teacher_profile_id where a.student_id=selected_id and ms.status<>'cancelled' and ms.scheduled_at>=now()-interval '30 days'),'[]'::jsonb),
    'assignments',coalesce((select jsonb_agg(row_data order by due_at) from (select jsonb_build_object('id',ass.id,'title',ass.title,'className',c.name,'dueAt',ass.due_at,'status',coalesce(sub.status,'pending'::public.assignment_submission_status),'feedback',sub.feedback) row_data,ass.due_at from public.assignments ass join public.classes c on c.id=ass.class_id left join public.assignment_submissions sub on sub.assignment_id=ass.id and sub.student_id=selected_id where exists(select 1 from public.enrollments e where e.class_id=ass.class_id and e.student_id=selected_id and e.status='active') order by (coalesce(sub.status,'pending'::public.assignment_submission_status)='reviewed'),ass.due_at limit 12) work),'[]'::jsonb),
    'announcements',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'title',a.title,'body',a.body,'publishedAt',a.published_at,'authorName',coalesce(p.display_name,'한살매')) order by a.published_at desc) from public.announcements a left join public.profiles p on p.id=a.author_profile_id where a.published_at is not null and a.published_at<=now() and (a.expires_at is null or a.expires_at>now()) and (a.audience='all' or (a.audience='student' and a.student_id=selected_id) or (a.audience='class' and exists(select 1 from public.enrollments e where e.student_id=selected_id and e.class_id=a.class_id and e.status='active'))) limit 10),'[]'::jsonb),
    'consultations',coalesce((select jsonb_agg(jsonb_build_object('id',con.id,'consultedAt',con.consulted_at,'type',con.consultation_type,'consultantName',coalesce(p.display_name,t.name,'담당 선생님'),'summary',case when viewer_role='student' then con.student_summary else con.guardian_summary end,'nextContactOn',con.next_contact_on) order by con.consulted_at desc) from public.consultations con left join public.profiles p on p.id=con.consultant_profile_id left join public.teachers t on t.id=con.teacher_id where con.student_id=selected_id and (case when viewer_role='student' then con.student_summary else con.guardian_summary end) is not null limit 10),'[]'::jsonb)
  ) into result;
  return result;
end
$function$
;

-- Participation-aware: staff_alimtalk_ready_students
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
      exists(select 1 from public.lessons l join public.internal_participating_attendance at on at.lesson_id=l.id and at.student_id=e.student_id where l.class_id=cs.class_id and l.lesson_date=d.occurrence_date and l.status='completed') completed
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
      exists(select 1 from public.lessons l join public.internal_participating_attendance at on at.lesson_id=l.id and at.student_id=e.student_id where l.class_id=x.class_id and l.lesson_date=x.replacement_date and l.status='completed')
    from public.schedule_exceptions x join public.class_schedules cs on cs.class_id=x.class_id and cs.weekday=extract(isodow from x.original_date)::smallint
    join public.classes c on c.id=x.class_id and c.active join public.enrollments e on e.class_id=c.id and e.status='active'
      and e.started_on<=x.replacement_date and (e.ended_on is null or e.ended_on>=x.replacement_date)
    join public.students s on s.id=e.student_id and s.status in ('active','재원')
    where x.kind in ('changed','makeup') and x.replacement_date between p_from and p_to
  ),
  class_makeups as (
    select distinct m.student_id,'class-makeup:'||m.class_id||':'||m.attendance_date expected_key,'보강수업',c.name,m.attendance_date,cs.start_time,
      exists(select 1 from public.lessons l join public.internal_participating_attendance at on at.lesson_id=l.id and at.student_id=m.student_id where l.class_id=m.class_id and l.lesson_date=m.attendance_date and l.status='completed')
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
  scheduled_expected_raw as (
    select * from regular_fixed union select * from regular_replacements union select * from class_makeups
    union all select * from special_lessons union all select * from correction_fixed union select * from correction_changes
  ),
 scheduled_expected as (select * from scheduled_expected_raw e where case when split_part(e.expected_key,':',1) in ('regular','class-makeup') then not public.internal_class_student_excluded(e.student_id,split_part(e.expected_key,':',2)::uuid,e.occurrence_date) else true end),
  expected as (
    select * from scheduled_expected
    union all
    select a.student_id,'recorded-regular:'||l.id::text,'정규수업',c.name,l.lesson_date,
      (l.starts_at at time zone 'Asia/Seoul')::time,true
    from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id
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
    'sourceVersion',md5(coalesce(src.lessons,'[]'::jsonb)::text),'lessons',coalesce(src.lessons,'[]'::jsonb),'recipient',coalesce(rec.recipient,jsonb_build_object('guardianName','','maskedPhone','','available',false))
  ) order by (r.completed_count=r.expected_count) desc,s.name,s.id),'[]'::jsonb) into result
  from readiness r join public.students s on s.id=r.student_id left join report_sources src on src.student_id=s.id left join recipients rec on rec.student_id=s.id where r.expected_count>0;
  return result;
end $function$
;

-- Participation-aware: family_today_lessons
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
    from public.lessons l join public.classes c on c.id=l.class_id left join public.profiles p on p.id=l.teacher_profile_id left join public.internal_participating_attendance a on a.lesson_id=l.id and a.student_id=sid where not public.internal_class_student_excluded(sid,c.id,today) and l.lesson_date=today and l.id=public.internal_student_class_lesson_id(sid,l.class_id,today) and (a.id is not null or (l.status<>'cancelled' and (
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
end $function$
;

-- Participation-aware: family_exam_progress
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
      from public.internal_participating_exams r join public.lessons l on l.id=r.lesson_id join public.classes c on c.id=l.class_id
      left join public.academy_subjects subject on subject.id=c.subject_id left join public.profiles p on p.id=coalesce(r.created_by,l.teacher_profile_id)
      where r.student_id=v_student_id and r.score is not null and l.status='completed'
        and l.id=public.internal_student_class_lesson_id(v_student_id,l.class_id,l.lesson_date)
        and r.id=public.internal_class_current_exam_id(l.id,v_student_id)
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
end $function$
;

-- Participation-aware: family_learning_calendar_schedule
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
  ), saved_source as (
    select l.*,a.status::text attendance_status,c.name,c.subject,c.room class_room
    from lessons l join classes c on c.id=l.class_id
    left join public.internal_participating_attendance a on a.lesson_id=l.id and a.student_id=sid
    where l.lesson_date between month_start and month_end and l.lesson_date<=(now() at time zone 'Asia/Seoul')::date
      and public.internal_student_has_class_record(sid,l.class_id,l.lesson_date)
      and l.id=public.internal_student_class_lesson_id(sid,l.class_id,l.lesson_date)
  ), saved_regular as (
    select 'regular-saved:'||id::text id,lesson_date class_date,
      (starts_at at time zone 'Asia/Seoul')::time start_time,(ends_at at time zone 'Asia/Seoul')::time end_time,
      'regular'::text kind,'정규수업'::text label,name title,subject,coalesce(room,class_room,'') room,
      case when status='cancelled' then 'cancelled' else 'scheduled' end state,attendance_status
    from saved_source
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
    where not public.internal_class_student_excluded(sid,c.id,d.class_date) and not exists(select 1 from saved_source l where l.class_id=c.id and l.lesson_date=d.class_date)
      and (not exists(select 1 from public.student_schedule_assignments ssa where ssa.student_id = sid)
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
      where s.class_id = c.id and s.weekday=extract(isodow from x.original_date)::smallint
        and (s.valid_from is null or s.valid_from<=x.original_date) and (s.valid_until is null or s.valid_until>=x.original_date)
        and public.student_uses_class_schedule(sid,s.id) order by s.start_time limit 1
    ) cs on true
    where not public.internal_class_student_excluded(sid,c.id,x.replacement_date) and x.replacement_date between month_start and month_end
      and x.kind in ('changed', 'makeup')
      and public.internal_student_regular_class_on(sid,c.id,x.original_date)
      and not exists(select 1 from saved_source l where l.class_id=c.id and l.lesson_date=x.replacement_date)
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
    select * from saved_regular
    union all select * from regular_base
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
$function$
;

-- Participation-aware: staff_class_agenda
CREATE OR REPLACE FUNCTION public.staff_class_agenda(p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
 if not public.is_staff() then raise exception '교직원만 조회할 수 있습니다.'; end if;
 with allowed as (
 select c.* from classes c where c.active and (public.current_user_role()='admin' or exists(select 1 from class_teachers t where t.class_id=c.id and t.profile_id=auth.uid()))
 ), slots as (
 select cs.id::text key,c.id class_id,null::uuid session_id,c.name,c.subject,c.color,c.room,cs.start_time,cs.end_time,'정규수업' kind
 from allowed c join class_schedules cs on cs.class_id=c.id
 where cs.weekday=extract(isodow from p_date) and (cs.valid_from is null or cs.valid_from<=p_date) and (cs.valid_until is null or cs.valid_until>=p_date)
 and not exists(select 1 from schedule_exceptions x where x.class_id=c.id and x.original_date=p_date and x.kind in ('cancelled','changed','makeup'))
 union all
 select x.id::text||':'||cs.id,c.id,null::uuid,c.name,c.subject,c.color,coalesce(x.room,c.room),coalesce(x.start_time,cs.start_time),coalesce(x.end_time,cs.end_time),case when x.kind='makeup' then '보강수업' else '변경수업' end
 from allowed c join schedule_exceptions x on x.class_id=c.id
 join class_schedules cs on cs.class_id=c.id and cs.weekday=extract(isodow from x.original_date)
 where x.replacement_date=p_date and x.kind in ('changed','makeup')
 ), makeup_slots as (
 select distinct on (m.class_id) 'makeup:'||m.class_id key,c.id class_id,null::uuid session_id,c.name,c.subject,c.color,c.room,
 coalesce((l.starts_at at time zone 'Asia/Seoul')::time,cs.start_time,'18:00'::time) start_time,
 coalesce((l.ends_at at time zone 'Asia/Seoul')::time,cs.end_time,'20:00'::time) end_time,'보강수업' kind
 from class_makeup_attendees m join allowed c on c.id=m.class_id
 left join lessons l on l.class_id=c.id and l.lesson_date=p_date
 left join class_schedules cs on cs.class_id=c.id
 where m.attendance_date=p_date and not exists(select 1 from slots s where s.class_id=c.id)
 order by m.class_id,l.starts_at,cs.start_time
 ), saved_slots as (
 select 'saved:'||l.id key,c.id class_id,null::uuid session_id,c.name,c.subject,c.color,coalesce(l.room,c.room) room,
 (l.starts_at at time zone 'Asia/Seoul')::time start_time,(l.ends_at at time zone 'Asia/Seoul')::time end_time,'정규수업'::text kind
 from allowed c join lessons l on l.class_id=c.id and l.lesson_date=p_date
 where l.id=public.internal_class_record_lesson_id(c.id,p_date)
 and (l.status='completed' or exists(select 1 from public.internal_participating_attendance a where a.lesson_id=l.id)
   or exists(select 1 from public.internal_participating_exams e where e.lesson_id=l.id) or exists(select 1 from public.internal_participating_homework h where h.lesson_id=l.id))
 and not exists(select 1 from slots s where s.class_id=c.id)
 and not exists(select 1 from makeup_slots s where s.class_id=c.id)
 ), all_slots as (
 select distinct on(class_id,start_time,end_time) * from (
 select * from slots union all select * from makeup_slots union all select * from saved_slots
 ) combined order by class_id,start_time,end_time,key
 ), entries as (
 select s.*, exists(select 1 from lessons l where l.class_id=s.class_id and l.lesson_date=p_date and l.status='completed') completed,
 (select count(*) from students st where st.status in ('active','재원') and public.student_attends_class_on(st.id,s.class_id,p_date) and not public.internal_class_student_excluded(st.id,s.class_id,p_date)) student_count,
 array(select t.profile_id from class_teachers t where t.class_id=s.class_id) teacher_ids
 from all_slots s
 union all
 select 'special:'||l.id,null::uuid,l.id,coalesce(a.name,'수업')||case when l.kind='makeup' then ' 보강' else ' 추가수업' end,
 coalesce(a.main_subject,a.name,'수업'),'#8e888b',l.room,l.starts_at,l.ends_at,case when l.kind='makeup' then '개별 보강' else '추가수업' end,
 l.status='completed',(select count(*) from teacher_special_lesson_students st where st.session_id=l.id),array[l.teacher_profile_id]
 from teacher_special_lessons l left join academy_subjects a on a.id=l.subject_id
 where l.lesson_date=p_date and (public.current_user_role()='admin' or l.teacher_profile_id=auth.uid())
 )
 select coalesce(jsonb_agg(jsonb_build_object('key',key,'classId',class_id,'sessionId',session_id,'name',name,'subject',subject,'color',color,'room',room,'startTime',to_char(start_time,'HH24:MI'),'endTime',to_char(end_time,'HH24:MI'),'kind',kind,'completed',completed,'studentCount',student_count,'teacherIds',teacher_ids) order by start_time,name),'[]'::jsonb) into result from entries;
 return result;
end $function$
;

-- Participation-aware: staff_class_day
CREATE OR REPLACE FUNCTION public.staff_class_day(p_class_id uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 수업 기록을 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  select jsonb_build_object('rosterVersion',public.internal_class_participation_version(p_class_id,p_date),'lessonId',l.id,'examContent',null,'lessonContent',null,'homeworkContent',null,
    'students',coalesce((select jsonb_agg(jsonb_build_object(
      'id',s.id,'name',s.name,'school',s.school,'grade',s.grade,'status',a.status,
      'lateMinutes',a.late_minutes,'absenceReason',a.absence_reason,'note',a.note,
      'excluded',public.internal_class_student_excluded(s.id,p_class_id,p_date),
      'exclusionReason',coalesce((select x.reason from public.class_lesson_participation x where x.class_id=p_class_id and x.lesson_date=p_date and x.student_id=s.id),''),
      'directAdded',exists(select 1 from public.class_lesson_roster_overrides o where o.class_id=p_class_id and o.lesson_date=p_date and o.student_id=s.id)
    ) order by s.name)
      from public.students s left join public.attendance a on a.student_id=s.id and a.lesson_id=l.id
      where public.student_attends_class_on(s.id,p_class_id,p_date)),'[]'::jsonb))
  into result from public.classes c left join lateral(select lesson.* from public.lessons lesson where lesson.class_id=c.id and lesson.lesson_date=p_date and lesson.id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by lesson.starts_at limit 1) l on true where c.id=p_class_id;
  return coalesce(result,jsonb_build_object('lessonId',null,'examContent',null,'lessonContent',null,'homeworkContent',null,'students','[]'::jsonb));
end $function$
;

-- Participation-aware: staff_set_class_lesson_state
CREATE OR REPLACE FUNCTION public.staff_set_class_lesson_state(p_class_id uuid, p_date date, p_state text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_lesson_id uuid; missing_names text;
begin
  if not public.is_staff() then raise exception '교직원만 수업 상태를 변경할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 수정할 수 있습니다.'; end if;
  if p_state not in ('draft','completed') then raise exception '수업 상태를 확인해 주세요.'; end if;
  v_lesson_id:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  if p_state='completed' then
    select string_agg(s.name,', ' order by s.name) into missing_names from public.students s
    where public.student_attends_class_on(s.id,p_class_id,p_date) and not public.internal_class_student_excluded(s.id,p_class_id,p_date)
      and not exists(select 1 from public.attendance a where a.lesson_id=v_lesson_id and a.student_id=s.id);
    if missing_names is not null then raise exception '출결 미입력 학생: %',missing_names; end if;
  end if;
  update public.lessons set status=p_state,updated_at=now() where id=v_lesson_id;
  return p_state;
end $function$
;

-- Participation-aware: staff_apply_class_revision_payload
CREATE OR REPLACE FUNCTION public.staff_apply_class_revision_payload(p_class_id uuid, p_date date, p_payload jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_lesson_id uuid;
  v_row jsonb;
  v_exam jsonb;
  v_student_id uuid;
  v_status text;
  v_late_minutes integer;
  v_absence_reason text;
  v_missing_names text;
  v_exam_payload jsonb;
  v_homework_payload jsonb;
begin
  if not public.is_staff() then
    raise exception '교직원만 수정 내용을 반영할 수 있습니다.';
  end if;
  if public.current_user_role() <> 'admin'
     and not exists (
       select 1 from public.class_teachers
       where class_id = p_class_id and profile_id = auth.uid()
     ) then
    raise exception '담당 클래스만 수정할 수 있습니다.';
  end if;
  if p_payload is null
     or jsonb_typeof(p_payload) <> 'object'
     or jsonb_typeof(coalesce(p_payload->'rows', 'null'::jsonb)) <> 'array' then
    raise exception '반영할 수업 내용을 확인해 주세요.';
  end if;

  select l.id into v_lesson_id
  from public.lessons l
  where l.class_id = p_class_id
    and l.lesson_date = p_date
    and l.status = 'completed'
  and l.id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by l.starts_at
  limit 1
  for update;

  if v_lesson_id is null then
    raise exception '완료된 수업의 수정 내용만 반영할 수 있습니다.';
  end if;

  select string_agg(s.name, ', ' order by s.name)
  into v_missing_names
  from public.students s
  where public.student_attends_class_on(s.id, p_class_id, p_date) and not public.internal_class_student_excluded(s.id,p_class_id,p_date)
    and not exists (
      select 1
      from jsonb_array_elements(p_payload->'rows') as draft_rows(item)
      where nullif(item->>'studentId', '')::uuid = s.id
        and item->>'status' in ('present', 'late', 'absent')
    );

  if v_missing_names is not null then
    raise exception '출결 미입력 학생: %', v_missing_names;
  end if;

  for v_row in select value from jsonb_array_elements(p_payload->'rows')
  loop
    v_student_id := nullif(v_row->>'studentId', '')::uuid;
    if v_student_id is null
       or not public.student_attends_class_on(v_student_id, p_class_id, p_date) then
      raise exception '이 날짜의 수업 명단에 없는 학생이 포함되어 있습니다.';
    end if;

    if public.internal_class_student_excluded(v_student_id,p_class_id,p_date) then continue; end if;
    v_status := v_row->>'status';
    v_late_minutes := nullif(v_row->>'lateMinutes', '')::integer;
    v_absence_reason := nullif(trim(v_row->>'absenceReason'), '');
    if v_status = 'late' and coalesce(v_late_minutes, 0) < 1 then
      raise exception '지각 시간을 입력해 주세요.';
    end if;
    if v_status = 'absent' and v_absence_reason is null then
      raise exception '결석 사유를 입력해 주세요.';
    end if;

    perform public.staff_save_class_attendance(
      p_class_id,
      p_date,
      v_student_id,
      v_status::public.attendance_status,
      case when v_status = 'late' then v_late_minutes else null end,
      case when v_status = 'absent' then v_absence_reason else null end,
      nullif(trim(v_row->>'note'), '')
    );

    v_exam := coalesce(v_row->'exam', '{}'::jsonb);
    if nullif(trim(v_exam->>'examType'), '') is null
       and nullif(trim(v_exam->>'examTitle'), '') is null
       and nullif(v_exam->>'score', '') is null
       and nullif(trim(v_exam->>'evaluation'), '') is null then
      delete from public.lesson_exam_results
      where lesson_id = v_lesson_id and student_id = v_student_id;
    end if;
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object(
    'studentId', item->>'studentId',
    'exams', jsonb_build_array(coalesce(item->'exam', '{}'::jsonb))
  )), '[]'::jsonb)
  into v_exam_payload
  from jsonb_array_elements(p_payload->'rows') as draft_rows(item);

  select coalesce(jsonb_agg(jsonb_build_object(
    'studentId', item->>'studentId',
    'lessonContent', item->>'lessonContent',
    'assignedHomework', item->>'assignedHomework',
    'inspectionStatus', item->>'inspectionStatus',
    'inspectionNote', item->>'inspectionNote'
  )), '[]'::jsonb)
  into v_homework_payload
  from jsonb_array_elements(p_payload->'rows') as draft_rows(item);

  perform public.staff_save_class_exam_results(p_class_id, p_date, v_exam_payload);
  perform public.staff_save_class_homework_results(p_class_id, p_date, v_homework_payload);
  perform public.staff_save_class_daily_notice(p_class_id, p_date, coalesce(p_payload->>'notice', ''));
  perform public.staff_save_class_lesson_content(p_class_id, p_date, coalesce(p_payload->>'lessonContent', ''));

  update public.lessons
  set status = 'completed',
      revision_draft = null,
      revision_saved_at = null,
      revision_saved_by = null,
      updated_at = now()
  where id = v_lesson_id;
end;
$function$
;

-- Participation-aware: staff_patch_class_record
CREATE OR REPLACE FUNCTION public.staff_patch_class_record(p_class_id uuid, p_date date, p_changes jsonb, p_expected_state text, p_mode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare snap jsonb; current_values jsonb; merged jsonb; payload jsonb; r record; row_value jsonb; row_payload jsonb;
 rows_payload jsonb:='[]'; exams jsonb:='[]'; homework jsonb:='[]'; lesson_id uuid; before_row jsonb; k text; change_exam boolean; change_hw boolean;
begin
 if auth.uid() is null or not public.is_staff() or
   (public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid())) then
  raise exception '담당 클래스만 수정할 수 있습니다.';
 end if;
 if p_mode not in ('draft','complete','revision','publish','attendance') or p_mode is null then raise exception '저장 방식을 확인해 주세요.'; end if;
 -- Serialize only this class/date, including the first save when no lesson row exists.
 perform pg_advisory_xact_lock(hashtextextended(p_class_id::text||':'||p_date::text,0));
 select id into lesson_id from public.lessons where class_id=p_class_id and lesson_date=p_date and id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by starts_at limit 1 for update;
 snap:=public.staff_class_edit_snapshot(p_class_id,p_date);
 if snap->>'state' is distinct from p_expected_state then raise exception '수업 완료 상태가 변경됐습니다. 입력 내용을 보관한 뒤 최신 기록을 확인해 주세요.'; end if;
 if (p_mode in ('revision','publish'))<>(p_expected_state='completed') then raise exception '수업 상태에 맞는 저장 버튼을 이용해 주세요.'; end if;
 current_values:=snap->'values';
 merged:=public.class_merge_edit_changes(current_values,p_changes);
 -- Identity is a dependency when changing an exam, not a user-editable field.
 if exists(select 1 from jsonb_array_elements(p_changes) c where c->'path'->>2='exam_id' and c->'before' is distinct from c->'value') then raise exception '시험 기록 식별자는 수정할 수 없습니다.'; end if;
 if p_mode='attendance' and exists(select 1 from jsonb_array_elements(p_changes) c where jsonb_array_length(c->'path')<>3 or c->'path'->>2 not in ('status','lateMinutes','absenceReason','note')) then raise exception '출결 항목만 저장할 수 있습니다.'; end if;
 for r in select * from jsonb_each(merged->'students') loop
  row_value:=r.value; before_row:=current_values->'students'->r.key;
  row_payload:=jsonb_build_object('studentId',r.key,'status',row_value->'status','lateMinutes',row_value->'lateMinutes',
   'absenceReason',row_value->>'absenceReason','note',row_value->>'note','lessonContent',row_value->>'lessonContent',
   'assignedHomework',row_value->>'assignedHomework','inspectionStatus',row_value->>'inspectionStatus','inspectionNote',row_value->>'inspectionNote',
   'exam',jsonb_build_object('id',nullif(row_value->>'exam_id',''),'examType',row_value->>'exam_examType','examTitle',row_value->>'exam_examTitle',
    'score',nullif(row_value->>'exam_score','')::numeric,'maxScore',coalesce(nullif(row_value->>'exam_maxScore','')::numeric,100),'evaluation',row_value->>'exam_evaluation','feedback',row_value->>'exam_feedback'));
  rows_payload:=rows_payload||jsonb_build_array(row_payload);
  if p_mode in ('revision','publish') or row_value=before_row or public.internal_class_student_excluded(r.key::uuid,p_class_id,p_date) then continue; end if;
  change_exam:=false; change_hw:=false;
  foreach k in array array['exam_examType','exam_examTitle','exam_score','exam_maxScore','exam_evaluation'] loop
   change_exam:=change_exam or row_value->k is distinct from before_row->k;
  end loop;
  foreach k in array array['lessonContent','assignedHomework','inspectionStatus','inspectionNote'] loop
   change_hw:=change_hw or row_value->k is distinct from before_row->k;
  end loop;
  if change_exam then exams:=exams||jsonb_build_array(jsonb_build_object('studentId',r.key,'exams',jsonb_build_array(row_payload->'exam'))); end if;
  if change_hw then homework:=homework||jsonb_build_array(row_payload-'exam'); end if;
  if row_value->'status' is distinct from before_row->'status' or row_value->'lateMinutes' is distinct from before_row->'lateMinutes'
    or row_value->'absenceReason' is distinct from before_row->'absenceReason' or row_value->'note' is distinct from before_row->'note' then
   if row_value->>'status' is null then perform public.staff_clear_class_attendance(p_class_id,p_date,r.key::uuid);
   else perform public.staff_save_class_attendance(p_class_id,p_date,r.key::uuid,(row_value->>'status')::public.attendance_status,
    nullif(row_value->>'lateMinutes','')::integer,nullif(row_value->>'absenceReason',''),nullif(row_value->>'note','')); end if;
  end if;
 end loop;
 payload:=jsonb_build_object('notice',merged->>'notice','lessonContent',merged->>'lessonContent','rows',rows_payload);
 if p_mode='revision' then perform public.staff_save_class_revision_draft(p_class_id,p_date,payload);
 elsif p_mode='publish' then perform public.staff_publish_class_revision(p_class_id,p_date,payload);
 else
  if jsonb_array_length(exams)>0 then perform public.staff_save_class_exam_results(p_class_id,p_date,exams); end if;
  if jsonb_array_length(homework)>0 then perform public.staff_save_class_homework_results(p_class_id,p_date,homework); end if;
  if merged->'notice' is distinct from current_values->'notice' then perform public.staff_save_class_daily_notice(p_class_id,p_date,merged->>'notice'); end if;
  if merged->'lessonContent' is distinct from current_values->'lessonContent' then perform public.staff_save_class_lesson_content(p_class_id,p_date,merged->>'lessonContent'); end if;
  if p_mode<>'attendance' then perform public.staff_set_class_lesson_state(p_class_id,p_date,case when p_mode='complete' then 'completed' else 'draft' end); end if;
 end if;
 return public.staff_class_edit_snapshot(p_class_id,p_date);
end $function$
;

-- Participation-aware: staff_save_class_attendance
CREATE OR REPLACE FUNCTION public.staff_save_class_attendance(p_class_id uuid, p_date date, p_student_id uuid, p_status attendance_status, p_late_minutes integer DEFAULT NULL::integer, p_absence_reason text DEFAULT NULL::text, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_lesson_id uuid;
begin
  v_lesson_id:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  if not public.student_attends_class_on(p_student_id,p_class_id,p_date) then raise exception '이 날짜의 수업 명단에 없는 학생입니다.'; end if;
  if p_status='late' and coalesce(p_late_minutes,0)<1 then raise exception '지각 시간을 입력해 주세요.'; end if;
  if p_status='absent' and nullif(trim(p_absence_reason),'') is null then raise exception '결석 사유를 입력해 주세요.'; end if;
  if public.internal_class_student_excluded(p_student_id,p_class_id,p_date) then raise exception '오늘 수업에서 제외된 학생입니다. 수업 대상에 다시 포함한 뒤 출결을 입력해 주세요.'; end if;
  insert into public.attendance as attendance_record(lesson_id,student_id,status,checked_at,note,makeup_required,late_minutes,absence_reason)
  values(v_lesson_id,p_student_id,p_status,now(),nullif(trim(p_note),''),p_status='absent',case when p_status='late' then p_late_minutes end,case when p_status='absent' then trim(p_absence_reason) end)
  on conflict(lesson_id,student_id) do update set status=excluded.status,checked_at=now(),note=excluded.note,makeup_required=excluded.makeup_required,late_minutes=excluded.late_minutes,absence_reason=excluded.absence_reason;
end $function$
;

-- Participation-aware: staff_class_homework_results
CREATE OR REPLACE FUNCTION public.staff_class_homework_results(p_class_id uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 숙제 결과를 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('studentId',s.id,'lessonContent',coalesce(current_result.lesson_content,''),'assignedHomework',coalesce(current_result.assigned_homework,''),'inspectionStatus',coalesce(current_result.inspection_status,current_result.status,''),'inspectionNote',coalesce(current_result.inspection_note,current_result.note,''),'previousHomework',coalesce(previous_result.assigned_homework,'')) order by s.name),'[]'::jsonb) into result
  from public.students s
  left join lateral(select id from public.lessons where class_id=p_class_id and lesson_date=p_date and id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by starts_at limit 1) lesson on true
  left join public.lesson_homework_results current_result on current_result.lesson_id=lesson.id and current_result.student_id=s.id
  left join lateral(select hr.assigned_homework from public.internal_participating_homework hr join public.lessons prior on prior.id=hr.lesson_id where prior.class_id=p_class_id and prior.lesson_date<p_date and hr.student_id=s.id and nullif(trim(hr.assigned_homework),'') is not null order by prior.lesson_date desc limit 1) previous_result on true
  where public.student_attends_class_on(s.id,p_class_id,p_date);
  return result;
end $function$
;

-- Participation-aware: staff_save_attendance
CREATE OR REPLACE FUNCTION public.staff_save_attendance(p_schedule_id uuid, p_date date, p_student_id uuid, p_status attendance_status, p_note text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  target_schedule public.class_schedules%rowtype;
  target_class public.classes%rowtype;
  target_lesson_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 출결을 입력할 수 있습니다.'; end if;
  select * into target_schedule from public.class_schedules where id = p_schedule_id;
  if target_schedule.id is null or target_schedule.weekday <> extract(isodow from p_date)::smallint then raise exception '선택한 날짜의 수업을 찾을 수 없습니다.'; end if;
  select * into target_class from public.classes where id = target_schedule.class_id and active;
  if target_class.id is null then raise exception '운영 중인 클래스를 찾을 수 없습니다.'; end if;
  if not exists (select 1 from public.enrollments e where e.class_id = target_class.id and e.student_id = p_student_id and e.status = 'active' and e.started_on <= p_date and (e.ended_on is null or e.ended_on >= p_date)) then raise exception '이 수업의 재원생이 아닙니다.'; end if;

  if public.internal_class_student_excluded(p_student_id,target_class.id,p_date) then raise exception '오늘 수업에서 제외된 학생입니다. 수업 대상에 다시 포함해 주세요.'; end if;
  insert into public.lessons(class_id, lesson_date, starts_at, ends_at, room)
  values (target_class.id, p_date, ((p_date + target_schedule.start_time) at time zone 'Asia/Seoul'), ((p_date + target_schedule.end_time) at time zone 'Asia/Seoul'), target_class.room)
  on conflict (class_id, starts_at) do update set ends_at = excluded.ends_at, room = excluded.room
  returning id into target_lesson_id;

  insert into public.attendance(lesson_id, student_id, status, checked_at, note, makeup_required)
  values (target_lesson_id, p_student_id, p_status, now(), nullif(trim(p_note), ''), p_status = 'absent')
  on conflict (lesson_id, student_id) do update
  set status = excluded.status, checked_at = excluded.checked_at, note = excluded.note, makeup_required = excluded.makeup_required;
end
$function$
;

-- Participation-aware: staff_mark_class_present
CREATE OR REPLACE FUNCTION public.staff_mark_class_present(p_schedule_id uuid, p_date date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  student_record record;
begin
  if not public.is_staff() then raise exception '교직원만 출결을 입력할 수 있습니다.'; end if;
  for student_record in
    select e.student_id, (
      select a.note from public.lessons l join public.attendance a on a.lesson_id = l.id
      where l.class_id = cs.class_id and l.starts_at = ((p_date + cs.start_time) at time zone 'Asia/Seoul') and a.student_id = e.student_id
    ) as existing_note
    from public.class_schedules cs
    join public.enrollments e on e.class_id = cs.class_id
    where not public.internal_class_student_excluded(e.student_id,cs.class_id,p_date) and cs.id = p_schedule_id and cs.weekday = extract(isodow from p_date)::smallint
      and e.status = 'active' and e.started_on <= p_date and (e.ended_on is null or e.ended_on >= p_date)
  loop
    perform public.staff_save_attendance(p_schedule_id, p_date, student_record.student_id, 'present', student_record.existing_note);
  end loop;
end
$function$
;