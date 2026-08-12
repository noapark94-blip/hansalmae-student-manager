create or replace function public.staff_class_lesson_history(
  p_class_id uuid,
  p_limit integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role public.user_role;
  v_result jsonb;
begin
  v_role := public.current_user_role();
  if v_role not in ('admin', 'teacher') then
    raise exception '교직원만 수업일지를 확인할 수 있습니다.';
  end if;

  if v_role = 'teacher' and not exists (
    select 1 from public.class_teachers ct
    where ct.class_id = p_class_id and ct.teacher_profile_id = auth.uid()
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
        'present', (select count(*) from public.attendance a where a.lesson_id = l.id and a.status = 'present'),
        'late', (select count(*) from public.attendance a where a.lesson_id = l.id and a.status = 'late'),
        'absent', (select count(*) from public.attendance a where a.lesson_id = l.id and a.status = 'absent'),
        'excused', (select count(*) from public.attendance a where a.lesson_id = l.id and a.status = 'excused'),
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
$$;

revoke all on function public.staff_class_lesson_history(uuid, integer) from public;
grant execute on function public.staff_class_lesson_history(uuid, integer) to authenticated;
