-- Preserve history; evaluate subject enrollment at the selected month boundary or today.
create or replace function public.staff_monthly_lesson_coverage(p_month date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
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
  select distinct a.student_id,c.main_subject from attendance a join lessons l on l.id=a.lesson_id join class_info c on c.id=l.class_id
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
  select a.student_id,c.main_subject from makeup_sessions ms join attendance a on a.id=ms.attendance_id join lessons l on l.id=a.lesson_id join class_info c on c.id=l.class_id
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
  from pairs p join attendance a on a.student_id=p.student_id join lessons l on l.id=a.lesson_id join class_info c on c.id=l.class_id and c.main_subject=p.subject
  where l.lesson_date between m and last_day and not exists(select 1 from planned q where q.student_id=p.student_id and q.class_id=c.id and q.class_date=l.lesson_date)
 ), regular_events as (
  select 'regular:'||q.class_id||':'||q.class_date id,q.student_id,q.subject,q.class_date,
   coalesce(l.starts_at,(q.class_date+q.start_time) at time zone 'Asia/Seoul') starts_at,c.name title,q.kind,
   case when l.status='cancelled' then 'cancelled' when a.status in ('present','late') and q.class_date<=today then 'attended'
    when a.status in ('absent','excused') then 'absent'
    when coalesce(l.starts_at,(q.class_date+q.start_time) at time zone 'Asia/Seoul')>now() then 'planned' else 'unrecorded' end state
  from class_days q join class_info c on c.id=q.class_id
  left join lessons l on l.id=public.internal_student_class_lesson_id(q.student_id,q.class_id,q.class_date)
  left join attendance a on a.lesson_id=l.id and a.student_id=q.student_id
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
  from pairs p join attendance a on a.student_id=p.student_id join lessons l on l.id=a.lesson_id join class_info c on c.id=l.class_id and c.main_subject=p.subject join makeup_sessions ms on ms.attendance_id=a.id
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
end $$;
revoke all on function public.staff_monthly_lesson_coverage(date) from public,anon;
grant execute on function public.staff_monthly_lesson_coverage(date) to authenticated;
