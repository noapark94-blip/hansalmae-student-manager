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
        'enrolled', (select count(*) from public.enrollments e where e.class_id = c.id and e.status = 'active' and e.started_on <= t.day and (e.ended_on is null or e.ended_on >= t.day) and not public.internal_class_student_excluded(e.student_id,c.id,t.day)),
        'present', (select count(*) from public.lessons l join public.internal_participating_attendance a on a.lesson_id = l.id where l.class_id = c.id and l.lesson_date = t.day and a.status = 'present')
      ) order by cs.start_time)
      from public.class_schedules cs
      join public.classes c on c.id = cs.class_id
      cross join today t
      where cs.weekday = t.weekday and c.active and (public.internal_academy_closure(t.day,'regular') is null or exists(select 1 from public.academy_day_openings o where o.kind='regular' and o.entity_id=c.id and o.lesson_date=t.day))
        and exists(select 1 from public.enrollments e where e.class_id=c.id and e.status='active' and e.started_on<=t.day and (e.ended_on is null or e.ended_on>=t.day) and not public.internal_class_student_excluded(e.student_id,c.id,t.day))
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
$function$;
