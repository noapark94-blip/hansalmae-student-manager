create or replace function public.staff_set_class_lesson_state(
  p_class_id uuid,
  p_date date,
  p_state text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lesson_id uuid;
  missing_names text;
begin
  if not public.is_staff() then
    raise exception '교직원만 수업 상태를 변경할 수 있습니다.';
  end if;
  if public.current_user_role() <> 'admin'
     and not exists (
       select 1 from public.class_teachers
       where class_id = p_class_id and profile_id = auth.uid()
     ) then
    raise exception '담당 클래스만 수정할 수 있습니다.';
  end if;
  if p_state not in ('draft', 'completed') then
    raise exception '수업 상태를 확인해 주세요.';
  end if;

  v_lesson_id := public.staff_save_class_day(p_class_id, p_date, null, null, null);

  if p_state = 'completed' then
    select string_agg(s.name, ', ' order by s.name)
    into missing_names
    from public.enrollments e
    join public.students s on s.id = e.student_id
    where e.class_id = p_class_id
      and e.status = 'active'
      and public.student_attends_class_on(s.id, p_class_id, p_date)
      and not exists (
        select 1 from public.attendance a
        where a.lesson_id = v_lesson_id and a.student_id = s.id
      );

    if missing_names is not null then
      raise exception '출결 미입력 학생: %', missing_names;
    end if;
  end if;

  update public.lessons l
  set status = p_state, updated_at = now()
  where l.id = v_lesson_id;

  return p_state;
end;
$$;

revoke all on function public.staff_set_class_lesson_state(uuid, date, text) from public, anon;
grant execute on function public.staff_set_class_lesson_state(uuid, date, text) to authenticated;
notify pgrst, 'reload schema';