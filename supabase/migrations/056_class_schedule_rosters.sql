create or replace function public.staff_class_schedule_rosters()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then
    raise exception '교직원만 수업 명단을 확인할 수 있습니다.';
  end if;

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'classId', c.id,
        'students', coalesce((
          select jsonb_agg(
            jsonb_build_object('id', s.id, 'name', s.name)
            order by s.name
          )
          from public.enrollments e
          join public.students s on s.id = e.student_id
          where e.class_id = c.id
            and e.status = 'active'
            and s.status = 'active'
        ), '[]'::jsonb)
      )
      order by c.name
    )
    from public.classes c
    where c.active = true
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.staff_class_schedule_rosters() from public;
grant execute on function public.staff_class_schedule_rosters() to authenticated;
