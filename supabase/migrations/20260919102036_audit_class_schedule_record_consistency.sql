create or replace function public.internal_student_has_class_record(p_student uuid,p_class uuid,p_date date)
returns boolean language sql stable security invoker set search_path=public as $$
 select exists(select 1 from lessons l where l.class_id=p_class and l.lesson_date=p_date and (
 exists(select 1 from attendance a where a.lesson_id=l.id and a.student_id=p_student)
 or exists(select 1 from lesson_homework_results h where h.lesson_id=l.id and h.student_id=p_student)
 or exists(select 1 from lesson_exam_results e where e.lesson_id=l.id and e.student_id=p_student)))
$$;

revoke all on function public.internal_student_has_class_record(uuid,uuid,date) from public,anon,authenticated;

create or replace function public.internal_student_regular_class_on(p_student uuid,p_class uuid,p_date date)
returns boolean language sql stable security invoker set search_path=public as $$
 select exists(select 1 from enrollments e join class_schedules cs on cs.class_id=e.class_id
 where e.student_id=p_student and e.class_id=p_class and e.status='active'
 and e.started_on<=p_date and (e.ended_on is null or e.ended_on>=p_date)
 and cs.weekday=extract(isodow from p_date)::smallint
 and (cs.valid_from is null or cs.valid_from<=p_date) and (cs.valid_until is null or cs.valid_until>=p_date)
 and public.student_uses_class_schedule(p_student,cs.id))
$$;

revoke all on function public.internal_student_regular_class_on(uuid,uuid,date) from public,anon,authenticated;

create or replace function public.student_attends_class_on(p_student_id uuid,p_class_id uuid,p_date date)
returns boolean language sql stable security definer set search_path=public as $$
 select public.internal_student_has_class_record(p_student_id,p_class_id,p_date)
 or exists(select 1 from class_makeup_attendees where student_id=p_student_id and class_id=p_class_id and attendance_date=p_date)
 or exists(select 1 from class_lesson_roster_overrides where student_id=p_student_id and class_id=p_class_id and lesson_date=p_date)
 or public.internal_student_regular_class_on(p_student_id,p_class_id,p_date)
 or exists(select 1 from schedule_exceptions x where x.class_id=p_class_id and x.replacement_date=p_date
   and x.kind in ('changed','makeup') and public.internal_student_regular_class_on(p_student_id,p_class_id,x.original_date))
$$;

create or replace function public.internal_student_class_lesson_id(p_student uuid,p_class uuid,p_date date)
returns uuid language sql stable security invoker set search_path=public as $$
 select l.id from lessons l where l.class_id=p_class and l.lesson_date=p_date
 order by (exists(select 1 from attendance a where a.lesson_id=l.id and a.student_id=p_student)
 or exists(select 1 from lesson_homework_results h where h.lesson_id=l.id and h.student_id=p_student)
 or exists(select 1 from lesson_exam_results e where e.lesson_id=l.id and e.student_id=p_student)) desc,
 (l.status='completed') desc,(l.status='cancelled'),l.starts_at,l.id limit 1
$$;

revoke all on function public.internal_student_class_lesson_id(uuid,uuid,date) from public,anon,authenticated;

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
    left join attendance a on a.lesson_id=l.id and a.student_id=sid
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
    where not exists(select 1 from saved_source l where l.class_id=c.id and l.lesson_date=d.class_date)
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
    where x.replacement_date between month_start and month_end
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
$function$;

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
    from public.lessons l join public.classes c on c.id=l.class_id left join public.profiles p on p.id=l.teacher_profile_id left join public.attendance a on a.lesson_id=l.id and a.student_id=sid where l.lesson_date=today and l.id=public.internal_student_class_lesson_id(sid,l.class_id,today) and (a.id is not null or (l.status<>'cancelled' and (
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
      join public.attendance a on a.lesson_id=l.id
      join public.students s on s.id=a.student_id
      where l.class_id=p_class_id and l.lesson_date=d.day::date
        and l.id=public.internal_student_class_lesson_id(s.id,p_class_id,d.day::date)
    ),'[]'::jsonb)
  ) order by d.day),'[]'::jsonb)
  into result
  from generate_series(first_day,last_day,interval '1 day') d(day);
  return result;
end $function$;

create or replace function public.internal_schedule_periods_overlap(a_from date,a_until date,b_from date,b_until date)
returns boolean language sql stable security invoker set search_path=public as $$
 select greatest(current_date,coalesce(a_from,current_date),coalesce(b_from,current_date))<=least(coalesce(a_until,'infinity'::date),coalesce(b_until,'infinity'::date))
$$;

revoke all on function public.internal_schedule_periods_overlap(date,date,date,date) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.assert_class_student_schedule_available(p_schedule_id uuid, p_class_id uuid, p_weekday smallint, p_start_time time without time zone, p_end_time time without time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare conflict_text text; schedule_window public.class_schedules%rowtype;
begin
  select * into schedule_window from public.class_schedules where id=p_schedule_id;
  if schedule_window.valid_until<current_date then return; end if;
  select s.name||' · '||c.name||' '||(array['월','화','수','목','금','토','일'])[p_weekday]||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI') into conflict_text
  from public.enrollments mine join public.students s on s.id=mine.student_id
  join public.enrollments other on other.student_id=mine.student_id and other.status='active' and other.class_id<>p_class_id
  join public.class_schedules cs on cs.class_id=other.class_id and cs.weekday=p_weekday join public.classes c on c.id=other.class_id and c.active
  where mine.class_id=p_class_id and mine.status='active'
    and public.student_uses_class_schedule(mine.student_id,p_schedule_id)
    and public.student_uses_class_schedule(mine.student_id,cs.id)
    and cs.start_time<p_end_time and cs.end_time>p_start_time and cs.id<>p_schedule_id
    and public.internal_schedule_periods_overlap(schedule_window.valid_from,schedule_window.valid_until,cs.valid_from,cs.valid_until)
  order by s.name,cs.start_time limit 1;
  if conflict_text is not null then raise exception '학생 시간 충돌: % 수업과 겹칩니다.',conflict_text; end if;

  select s.name||' · '||coalesce(a.subject,'첨삭')||' 첨삭 '||to_char(public.correction_time_start(a.start_time,a.slot_index),'HH24:MI')||'–'||to_char(public.correction_time_end(a.end_time,a.slot_index),'HH24:MI') into conflict_text
  from public.enrollments e join public.students s on s.id=e.student_id
  join public.correction_assignments a on a.student_id=e.student_id and a.active and a.weekday=p_weekday
    and public.internal_schedule_periods_overlap(schedule_window.valid_from,schedule_window.valid_until,a.valid_from,a.valid_until)
  where e.class_id=p_class_id and e.status='active' and public.student_uses_class_schedule(e.student_id,p_schedule_id)
    and public.correction_time_start(a.start_time,a.slot_index)<p_end_time and public.correction_time_end(a.end_time,a.slot_index)>p_start_time
  order by s.name,public.correction_time_start(a.start_time,a.slot_index) limit 1;
  if conflict_text is not null then raise exception '학생 시간 충돌: % 고정시간과 겹칩니다.',conflict_text; end if;

  select s.name||' · '||coalesce(a.subject,'첨삭')||' 첨삭 일정변경 '||to_char(x.target_date,'YYYY-MM-DD')||' '||
    to_char(x.target_start_time,'HH24:MI')||'–'||to_char(x.target_end_time,'HH24:MI') into conflict_text
  from public.enrollments e join public.students s on s.id=e.student_id
  join public.correction_assignments a on a.student_id=e.student_id
  join public.correction_schedule_exceptions x on x.assignment_id=a.id and x.kind in ('move','extra')
  where e.class_id=p_class_id and e.status='active' and public.student_uses_class_schedule(e.student_id,p_schedule_id)
    and (schedule_window.valid_from is null or schedule_window.valid_from<=x.target_date) and (schedule_window.valid_until is null or schedule_window.valid_until>=x.target_date)
    and x.target_date>=current_date and extract(isodow from x.target_date)::smallint=p_weekday
    and x.target_start_time<p_end_time and x.target_end_time>p_start_time
  order by x.target_date,s.name limit 1;
  if conflict_text is not null then raise exception '학생 시간 충돌: % 시간과 겹칩니다.',conflict_text; end if;
end $function$;

CREATE OR REPLACE FUNCTION public.assert_student_schedule_selection_available(p_student_id uuid, p_schedule_ids uuid[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare requested uuid[]:=coalesce(p_schedule_ids,'{}'::uuid[]); conflict_text text; student_name text;
begin
  select name into student_name from public.students where id=p_student_id;
  select c1.name||' '||to_char(cs1.start_time,'HH24:MI')||'–'||to_char(cs1.end_time,'HH24:MI')||
    ' / '||c2.name||' '||to_char(cs2.start_time,'HH24:MI')||'–'||to_char(cs2.end_time,'HH24:MI')
  into conflict_text
  from unnest(requested) a(id)
  join public.class_schedules cs1 on cs1.id=a.id
  join public.classes c1 on c1.id=cs1.class_id
  join unnest(requested) b(id) on b.id>a.id
  join public.class_schedules cs2 on cs2.id=b.id
  join public.classes c2 on c2.id=cs2.class_id
  where cs1.weekday=cs2.weekday and c1.active and c2.active
    and public.internal_schedule_periods_overlap(cs1.valid_from,cs1.valid_until,cs2.valid_from,cs2.valid_until)
    and cs1.start_time<cs2.end_time and cs1.end_time>cs2.start_time
    and daterange(coalesce(cs1.valid_from,'-infinity'::date),coalesce(cs1.valid_until,'infinity'::date),'[]')
      && daterange(coalesce(cs2.valid_from,'-infinity'::date),coalesce(cs2.valid_until,'infinity'::date),'[]')
  order by cs1.weekday,cs1.start_time limit 1;
  if conflict_text is not null then
    raise exception '학생 시간 충돌: % · % 수업 시간이 겹칩니다.',student_name,conflict_text;
  end if;

  select c.name||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI')||
    ' / '||coalesce(a.subject,'첨삭')||' 첨삭 '||
    to_char(public.correction_time_start(a.start_time,a.slot_index),'HH24:MI')||'–'||
    to_char(public.correction_time_end(a.end_time,a.slot_index),'HH24:MI')
  into conflict_text
  from unnest(requested) r(id)
  join public.class_schedules cs on cs.id=r.id
  join public.classes c on c.id=cs.class_id
  join public.correction_assignments a on a.student_id=p_student_id and a.active and a.weekday=cs.weekday
  where c.active and public.internal_schedule_periods_overlap(cs.valid_from,cs.valid_until,a.valid_from,a.valid_until)
    and public.correction_time_start(a.start_time,a.slot_index)<cs.end_time
    and public.correction_time_end(a.end_time,a.slot_index)>cs.start_time
    and daterange(coalesce(cs.valid_from,'-infinity'::date),coalesce(cs.valid_until,'infinity'::date),'[]')
      && daterange(a.valid_from,coalesce(a.valid_until,'infinity'::date),'[]')
  order by cs.weekday,cs.start_time limit 1;
  if conflict_text is not null then
    raise exception '학생 시간 충돌: % · % 시간이 겹칩니다.',student_name,conflict_text;
  end if;

  select c.name||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI')||
    ' / 첨삭 일정변경 '||to_char(x.target_date,'YYYY-MM-DD')||' '||
    to_char(x.target_start_time,'HH24:MI')||'–'||to_char(x.target_end_time,'HH24:MI')
  into conflict_text
  from unnest(requested) r(id)
  join public.class_schedules cs on cs.id=r.id
  join public.classes c on c.id=cs.class_id
  join public.correction_assignments a on a.student_id=p_student_id
  join public.correction_schedule_exceptions x on x.assignment_id=a.id and x.kind in ('move','extra')
  where x.target_date>=current_date and extract(isodow from x.target_date)::smallint=cs.weekday
    and (cs.valid_from is null or cs.valid_from<=x.target_date)
    and (cs.valid_until is null or cs.valid_until>=x.target_date)
    and x.target_start_time<cs.end_time and x.target_end_time>cs.start_time
  order by x.target_date,cs.start_time limit 1;
  if conflict_text is not null then
    raise exception '학생 시간 충돌: % · % 시간이 겹칩니다.',student_name,conflict_text;
  end if;
end $function$;

CREATE OR REPLACE FUNCTION public.staff_guard_class_schedule(p_id uuid, p_class_id uuid, p_base jsonb, p_values jsonb, p_delete boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v jsonb; current_teachers jsonb; result_id uuid; assigned_names text;
begin
 if auth.uid() is null or not coalesce(public.is_staff(),false) then raise exception '수업 배정 권한이 없습니다.'; end if;
 perform pg_advisory_xact_lock(hashtext('hansalmae_class_schedule_save'));
 perform 1 from public.classes where id=p_class_id and active for update;
 if not found then raise exception '운영 중인 클래스를 찾을 수 없습니다.'; end if;
 select coalesce(jsonb_agg(profile_id::text order by profile_id),'[]'::jsonb) into current_teachers from public.class_teachers where class_id=p_class_id;
 if p_id is not null then
   select jsonb_build_object('weekday',weekday,'startTime',to_char(start_time,'HH24:MI'),'endTime',to_char(end_time,'HH24:MI'),'teacherIds',current_teachers)
   into v from public.class_schedules where id=p_id and class_id=p_class_id for update;
   if not found then raise exception '이미 변경되거나 삭제된 수업 배정입니다. 창을 다시 열어 주세요.'; end if;
 else
   v:=jsonb_build_object('teacherIds',current_teachers);
 end if;
 if v is distinct from p_base then raise exception '다른 선생님이 수업 시간 또는 담당을 변경했습니다. 입력 내용은 유지됩니다. 최신 시간표를 확인한 뒤 다시 열어 주세요.'; end if;
 if p_delete then
   if p_id is null then raise exception '삭제할 배정이 없습니다.'; end if;
   select string_agg(s.name,', ' order by s.name) into assigned_names from public.student_schedule_assignments a join public.students s on s.id=a.student_id where a.class_schedule_id=p_id;
   if assigned_names is not null then raise exception '개별 수강요일 확인: %. 학생의 수강요일을 먼저 조정한 뒤 삭제해 주세요.',assigned_names; end if;
   delete from public.class_schedules where id=p_id;
   return p_id;
 end if;
 result_id:=public.staff_save_class_schedule(p_id,p_class_id,(p_values->>'weekday')::smallint,(p_values->>'startTime')::time,(p_values->>'endTime')::time,array(select jsonb_array_elements_text(p_values->'teacherIds')::uuid));
 return result_id;
end $function$;

create or replace function public.prevent_class_schedule_conflict()
returns trigger language plpgsql security definer set search_path=public as $$
declare conflict_text text;
begin
 if tg_table_name='class_schedules' then
  perform public.assert_class_student_schedule_available(new.id,new.class_id,new.weekday,new.start_time,new.end_time);
  select p.display_name||' · '||c.name||' '||(array['월','화','수','목','금','토','일'])[cs.weekday]||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI') into conflict_text
  from class_teachers mine join class_teachers theirs on theirs.profile_id=mine.profile_id and theirs.class_id<>new.class_id
  join profiles p on p.id=mine.profile_id join classes c on c.id=theirs.class_id and c.active
  join class_schedules cs on cs.class_id=c.id
  where mine.class_id=new.class_id and cs.weekday=new.weekday and cs.start_time<new.end_time and cs.end_time>new.start_time and cs.id<>new.id
   and public.internal_schedule_periods_overlap(new.valid_from,new.valid_until,cs.valid_from,cs.valid_until)
  order by cs.start_time,c.name,p.display_name limit 1;
  if conflict_text is not null then raise exception '선생님 시간 충돌: % 수업과 겹칩니다.',conflict_text; end if;
  select mine.room||' · '||other.name||' '||(array['월','화','수','목','금','토','일'])[cs.weekday]||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI') into conflict_text
  from class_schedules cs join classes mine on mine.id=new.class_id join classes other on other.id=cs.class_id and other.active
  where cs.id<>new.id and cs.weekday=new.weekday and cs.start_time<new.end_time and cs.end_time>new.start_time
   and nullif(trim(mine.room),'') is not null and mine.room=other.room
   and public.internal_schedule_periods_overlap(new.valid_from,new.valid_until,cs.valid_from,cs.valid_until)
  order by cs.start_time,other.name limit 1;
  if conflict_text is not null then raise exception '강의실 시간 충돌: % 수업과 겹칩니다.',conflict_text; end if;
 else
  select p.display_name||' · '||c.name||' '||(array['월','화','수','목','금','토','일'])[other.weekday]||' '||to_char(other.start_time,'HH24:MI')||'–'||to_char(other.end_time,'HH24:MI') into conflict_text
  from class_schedules mine join class_teachers ct on ct.profile_id=new.profile_id and ct.class_id<>new.class_id
  join profiles p on p.id=ct.profile_id join classes c on c.id=ct.class_id and c.active join class_schedules other on other.class_id=ct.class_id
  where mine.class_id=new.class_id and mine.weekday=other.weekday and mine.start_time<other.end_time and mine.end_time>other.start_time
   and public.internal_schedule_periods_overlap(mine.valid_from,mine.valid_until,other.valid_from,other.valid_until)
  order by other.weekday,other.start_time,c.name limit 1;
  if conflict_text is not null then raise exception '선생님 시간 충돌: % 수업과 겹칩니다.',conflict_text; end if;
 end if;
 return new;
end $$;
CREATE OR REPLACE FUNCTION public.staff_class_family_report_read_status(p_class_id uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_lesson_id uuid;
  v_students jsonb;
  v_total integer := 0;
  v_linked integer := 0;
  v_confirmed integer := 0;
begin
  if not public.is_staff() then
    raise exception '교직원만 학부모 확인 현황을 볼 수 있습니다.';
  end if;

  if public.current_user_role() <> 'admin' and not exists (
    select 1
    from public.class_teachers ct
    where ct.class_id = p_class_id and ct.profile_id = auth.uid()
  ) then
    raise exception '담당 클래스의 확인 현황만 볼 수 있습니다.';
  end if;

  select l.id into v_lesson_id
  from public.lessons l
  where l.class_id = p_class_id and l.lesson_date = p_date
  and l.id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by l.starts_at
  limit 1;

  select
    count(*)::integer,
    count(*) filter (where guardian_count > 0)::integer,
    count(*) filter (where guardian_count > 0 and read_count > 0)::integer,
    coalesce(jsonb_agg(jsonb_build_object(
      'studentId', student_id,
      'studentName', student_name,
      'school', school,
      'grade', grade,
      'guardianCount', guardian_count,
      'readCount', read_count,
      'status', case
        when guardian_count = 0 then 'unlinked'
        when read_count > 0 then 'confirmed'
        else 'unconfirmed'
      end,
      'viewedAt', viewed_at
    ) order by student_name), '[]'::jsonb)
  into v_total, v_linked, v_confirmed, v_students
  from (
    select
      s.id as student_id,
      s.name as student_name,
      s.school,
      s.grade,
      (
        select count(distinct g.profile_id)::integer
        from public.student_guardians sg
        join public.guardians g on g.id = sg.guardian_id
        where sg.student_id = s.id and g.profile_id is not null
      ) as guardian_count,
      case when v_lesson_id is null then 0 else (
        select count(distinct r.viewer_profile_id)::integer
        from public.family_learning_report_reads r
        join public.guardians g on g.profile_id = r.viewer_profile_id
        join public.student_guardians sg on sg.guardian_id = g.id and sg.student_id = s.id
        where r.lesson_id = v_lesson_id and r.student_id = s.id
      ) end as read_count,
      case when v_lesson_id is null then null else (
        select max(r.viewed_at)
        from public.family_learning_report_reads r
        join public.guardians g on g.profile_id = r.viewer_profile_id
        join public.student_guardians sg on sg.guardian_id = g.id and sg.student_id = s.id
        where r.lesson_id = v_lesson_id and r.student_id = s.id
      ) end as viewed_at
    from public.students s
    where public.student_attends_class_on(s.id, p_class_id, p_date)
  ) student_rows;

  return jsonb_build_object(
    'lessonId', v_lesson_id,
    'totalStudents', coalesce(v_total, 0),
    'linkedStudents', coalesce(v_linked, 0),
    'confirmedStudents', coalesce(v_confirmed, 0),
    'unconfirmedStudents', greatest(coalesce(v_linked, 0) - coalesce(v_confirmed, 0), 0),
    'unlinkedStudents', greatest(coalesce(v_total, 0) - coalesce(v_linked, 0), 0),
    'students', coalesce(v_students, '[]'::jsonb)
  );
end;
$function$;
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
 and (l.status='completed' or exists(select 1 from attendance a where a.lesson_id=l.id)
   or exists(select 1 from lesson_exam_results e where e.lesson_id=l.id) or exists(select 1 from lesson_homework_results h where h.lesson_id=l.id))
 and not exists(select 1 from slots s where s.class_id=c.id)
 and not exists(select 1 from makeup_slots s where s.class_id=c.id)
 ), all_slots as (
 select distinct on(class_id,start_time,end_time) * from (
 select * from slots union all select * from makeup_slots union all select * from saved_slots
 ) combined order by class_id,start_time,end_time,key
 ), entries as (
 select s.*, exists(select 1 from lessons l where l.class_id=s.class_id and l.lesson_date=p_date and l.status='completed') completed,
 (select count(*) from students st where st.status in ('active','재원') and public.student_attends_class_on(st.id,s.class_id,p_date)) student_count,
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
end $function$;

create or replace function public.staff_save_class_day(p_class_id uuid,p_date date,p_exam_content text,p_lesson_content text,p_homework_content text)
returns uuid language plpgsql security definer set search_path=public as $$
declare schedule_row public.class_schedules; result_id uuid; v_start time; v_end time; replacement_row public.schedule_exceptions;
begin
  if not public.is_staff() then raise exception '교직원만 수업 기록을 저장할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 수정할 수 있습니다.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_class_id::text||':'||p_date::text,0));
  select id into result_id from public.lessons
  where id=public.internal_class_record_lesson_id(p_class_id,p_date) for update;
  if result_id is not null then return result_id; end if;
  select * into replacement_row from public.schedule_exceptions where class_id=p_class_id and replacement_date=p_date and kind in ('changed','makeup') order by id limit 1;
  select * into schedule_row from public.class_schedules where class_id=p_class_id
    and weekday=extract(isodow from coalesce(replacement_row.original_date,p_date))::smallint
    and (valid_from is null or valid_from<=coalesce(replacement_row.original_date,p_date))
    and (valid_until is null or valid_until>=coalesce(replacement_row.original_date,p_date)) order by start_time limit 1;
  if replacement_row.id is null and exists(select 1 from public.schedule_exceptions where class_id=p_class_id and original_date=p_date and kind in ('cancelled','changed','makeup')) then schedule_row:=null; end if;
  if schedule_row.id is null and replacement_row.id is null and not exists(select 1 from public.class_makeup_attendees where class_id=p_class_id and attendance_date=p_date) then raise exception '정규 수업이 없는 날짜입니다. 보충 학생을 먼저 추가해 주세요.'; end if;
  v_start:=coalesce(replacement_row.start_time,schedule_row.start_time,'18:00'::time); v_end:=coalesce(replacement_row.end_time,schedule_row.end_time,'20:00'::time);
  insert into public.lessons(class_id,lesson_date,starts_at,ends_at,room,teacher_profile_id,updated_at)
  select c.id,p_date,((p_date+v_start) at time zone 'Asia/Seoul'),((p_date+v_end) at time zone 'Asia/Seoul'),coalesce(replacement_row.room,c.room),auth.uid(),now() from public.classes c where c.id=p_class_id
  on conflict(class_id,starts_at) do update set teacher_profile_id=auth.uid(),updated_at=now()
  returning id into result_id;
  return result_id;
end $$;

create or replace function public.internal_class_current_exam_id(p_lesson uuid,p_student uuid)
returns uuid language sql stable security invoker set search_path=public as $$
 select id from lesson_exam_results where lesson_id=p_lesson and student_id=p_student order by created_at,id limit 1
$$;
revoke all on function public.internal_class_current_exam_id(uuid,uuid) from public,anon,authenticated;

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
      'exams',coalesce((select jsonb_agg(jsonb_build_object('id',er.id,'examType',coalesce(er.exam_type,''),'examTitle',coalesce(er.exam_title,''),'score',er.score,'maxScore',coalesce(er.max_score,100),'percent',case when er.score is null or coalesce(er.max_score,0)<=0 then null else round(er.score/er.max_score*100,1) end,'evaluation',coalesce(er.evaluation,''),'feedback',coalesce(er.feedback,'')) order by er.created_at,er.id) from public.lesson_exam_results er where er.lesson_id=l.id and er.student_id=selected_id and er.id=public.internal_class_current_exam_id(l.id,selected_id) and (er.score is not null or nullif(trim(concat_ws(' ',er.exam_type,er.exam_title,er.evaluation,er.feedback)),'') is not null)),'[]'::jsonb)
    ) report_row,l.lesson_date,l.starts_at
    from public.lessons l join public.classes c on c.id=l.class_id 
    left join public.profiles tp on tp.id=l.teacher_profile_id left join public.attendance a on a.lesson_id=l.id and a.student_id=selected_id left join public.lesson_homework_results hr on hr.lesson_id=l.id and hr.student_id=selected_id
    left join public.class_daily_notices n on n.class_id=l.class_id and n.notice_date=l.lesson_date
    where l.status='completed' and (exists(select 1 from public.enrollments e where e.class_id=c.id and e.student_id=selected_id and e.started_on<=l.lesson_date and (e.ended_on is null or e.ended_on>=l.lesson_date)) or (l.status='completed' and a.id is not null)) and l.lesson_date<=current_date and (a.id is not null or hr.id is not null or nullif(trim(l.lesson_content),'') is not null or nullif(trim(l.homework_content),'') is not null or nullif(trim(l.exam_content),'') is not null or exists(select 1 from public.lesson_exam_results er where er.lesson_id=l.id and er.student_id=selected_id and er.id=public.internal_class_current_exam_id(l.id,selected_id) and (er.score is not null or nullif(trim(concat_ws(' ',er.exam_type,er.exam_title,er.evaluation,er.feedback)),'') is not null)))
    order by l.lesson_date desc,l.starts_at desc limit safe_limit
  ) reports;
  return result;
end $function$
;

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
      'exams',coalesce((select jsonb_agg(jsonb_build_object('id',er.id,'examType',coalesce(er.exam_type,''),'examTitle',coalesce(er.exam_title,''),'score',er.score,'maxScore',coalesce(er.max_score,100),'percent',case when er.score is null or coalesce(er.max_score,0)<=0 then null else round(er.score/er.max_score*100,1) end,'evaluation',coalesce(er.evaluation,''),'feedback',coalesce(er.feedback,'')) order by er.created_at,er.id) from public.lesson_exam_results er where er.lesson_id=l.id and er.student_id=selected_id and er.id=public.internal_class_current_exam_id(l.id,selected_id) and (er.score is not null or nullif(trim(concat_ws(' ',er.exam_type,er.exam_title,er.evaluation,er.feedback)),'') is not null)),'[]'::jsonb)
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
end $function$
;

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
end $function$;
