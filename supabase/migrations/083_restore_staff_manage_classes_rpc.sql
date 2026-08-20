create or replace function public.staff_manage_classes()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  if not public.is_staff() then
    raise exception '교직원만 클래스 목록을 확인할 수 있습니다.';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'id', c.id,
        'name', c.name,
        'subject', c.subject,
        'subjectId', c.subject_id,
        'room', c.room,
        'color', c.color,
        'active', c.active,
        'schedules', coalesce((
          select jsonb_agg(
            jsonb_build_object(
              'id', cs.id,
              'weekday', cs.weekday,
              'startTime', to_char(cs.start_time,'HH24:MI:SS'),
              'endTime', to_char(cs.end_time,'HH24:MI:SS')
            ) order by cs.weekday, cs.start_time
          )
          from public.class_schedules cs
          where cs.class_id=c.id
            and (cs.valid_until is null or cs.valid_until>=current_date)
        ), '[]'::jsonb),
        'teachers', coalesce((
          select jsonb_agg(
            jsonb_build_object('id',p.id,'name',p.display_name)
            order by p.display_name
          )
          from public.class_teachers ct
          join public.profiles p on p.id=ct.profile_id
          where ct.class_id=c.id
        ), '[]'::jsonb),
        'enrollmentCount', (select count(*) from public.enrollments e where e.class_id=c.id and e.status::text='active'),
        'scheduleCount', (select count(*) from public.class_schedules cs where cs.class_id=c.id),
        'lessonCount', (select count(*) from public.lessons l where l.class_id=c.id),
        'assignmentCount', (select count(*) from public.assignments a where a.class_id=c.id)
      ) order by c.active desc, c.subject, c.name
    )
    from public.classes c
    where public.current_user_role()='admin'
       or exists(select 1 from public.class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid())
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.staff_manage_classes() from public;
grant execute on function public.staff_manage_classes() to authenticated;
