-- 가족용 학습캘린더에 월별 예정 수업(정규·첨삭·보강·추가)을 제공합니다.

create or replace function public.family_learning_calendar_schedule(
  p_student_id uuid default null,
  p_month date default date_trunc('month', timezone('Asia/Seoul', now()))::date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
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
      d.class_date,
      cs.start_time,
      cs.end_time,
      'regular'::text as kind,
      '정규수업'::text as label,
      c.name as title,
      c.subject,
      coalesce(c.room, '') as room,
      'scheduled'::text as state,
      null::text as attendance_status
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
      'regular-change:' || x.id::text as id,
      x.replacement_date as class_date,
      coalesce(x.start_time, cs.start_time) as start_time,
      coalesce(x.end_time, cs.end_time) as end_time,
      case when x.kind = 'makeup' then 'makeup' else 'regular' end as kind,
      case when x.kind = 'makeup' then '보강' else '변경수업' end as label,
      c.name as title,
      c.subject,
      coalesce(x.room, c.room, '') as room,
      'scheduled'::text as state,
      null::text as attendance_status
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
      d.class_date,
      a.start_time,
      a.end_time,
      'correction'::text as kind,
      '첨삭'::text as label,
      coalesce(a.subject, '첨삭') || ' 첨삭수업' as title,
      coalesce(a.subject, '첨삭') as subject,
      ''::text as room,
      'scheduled'::text as state,
      null::text as attendance_status
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
      'correction-change:' || x.id::text as id,
      x.target_date as class_date,
      coalesce(x.target_start_time, a.start_time) as start_time,
      coalesce(x.target_end_time, a.end_time) as end_time,
      'correction'::text as kind,
      case when x.kind = 'extra' then '추가 첨삭' else '변경 첨삭' end as label,
      coalesce(a.subject, '첨삭') || ' 첨삭수업' as title,
      coalesce(a.subject, '첨삭') as subject,
      ''::text as room,
      'scheduled'::text as state,
      null::text as attendance_status
    from public.correction_schedule_exceptions x
    join public.correction_assignments a on a.id = x.assignment_id and a.student_id = sid
    where x.target_date between month_start and month_end and x.kind in ('move', 'extra')
  ), special as (
    select
      'special:' || l.id::text as id,
      l.lesson_date as class_date,
      l.starts_at as start_time,
      l.ends_at as end_time,
      case when l.kind = 'makeup' then 'makeup' else 'extra' end as kind,
      case when l.kind = 'makeup' then '보강' else '추가수업' end as label,
      coalesce(s.name, case when l.kind = 'makeup' then '보강수업' else '추가수업' end) as title,
      coalesce(s.name, '개별수업') as subject,
      coalesce(l.room, '') as room,
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
    'id', id,
    'date', to_char(class_date, 'YYYY-MM-DD'),
    'startTime', to_char(start_time, 'HH24:MI'),
    'endTime', to_char(end_time, 'HH24:MI'),
    'kind', kind,
    'label', label,
    'title', title,
    'subject', subject,
    'room', room,
    'state', state,
    'attendanceStatus', attendance_status
  ) order by class_date, start_time, id), '[]'::jsonb) into result from rows;

  return result;
end;
$$;

revoke all on function public.family_learning_calendar_schedule(uuid, date) from public, anon;
grant execute on function public.family_learning_calendar_schedule(uuid, date) to authenticated;
notify pgrst, 'reload schema';
