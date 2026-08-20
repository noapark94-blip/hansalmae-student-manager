-- 클래스·첨삭 기록의 진행 상태와 출결 완료 기준 통일

update public.lessons l
set status = case
  when exists (select 1 from public.attendance a where a.lesson_id = l.id) then 'completed'
  else 'draft'
end
where coalesce(l.status, 'scheduled') in ('scheduled', 'draft', 'completed');

update public.correction_reports
set published = false, updated_at = now()
where attendance_status = 'scheduled' and published = true;

create or replace function public.staff_class_lesson_state(
  p_class_id uuid,
  p_date date
)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result text;
begin
  if not public.is_staff() then
    raise exception '교직원만 수업 상태를 확인할 수 있습니다.';
  end if;
  if public.current_user_role() <> 'admin'
     and not exists (
       select 1 from public.class_teachers
       where class_id = p_class_id and profile_id = auth.uid()
     ) then
    raise exception '담당 클래스만 확인할 수 있습니다.';
  end if;

  select case when l.status = 'completed' then 'completed' else 'draft' end
  into result
  from public.lessons l
  where l.class_id = p_class_id and l.lesson_date = p_date
  order by l.starts_at
  limit 1;

  return coalesce(result, 'draft');
end;
$$;

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
  lesson_id uuid;
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

  lesson_id := public.staff_save_class_day(p_class_id, p_date, null, null, null);

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
        where a.lesson_id = lesson_id and a.student_id = s.id
      );

    if missing_names is not null then
      raise exception '출결 미입력 학생: %', missing_names;
    end if;
  end if;

  update public.lessons
  set status = p_state, updated_at = now()
  where id = lesson_id;

  return p_state;
end;
$$;

create or replace function public.staff_student_completed_learning_history(
  p_student_id uuid,
  p_limit integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  raw_rows jsonb;
  result jsonb;
begin
  raw_rows := public.staff_student_learning_history(p_student_id, p_limit);

  select coalesce(jsonb_agg(entry.item order by entry.ord), '[]'::jsonb)
  into result
  from jsonb_array_elements(coalesce(raw_rows, '[]'::jsonb)) with ordinality entry(item, ord)
  join public.lessons l on l.id = (entry.item->>'lessonId')::uuid
  where l.status = 'completed'
    and jsonb_typeof(entry.item->'attendance') = 'object';

  return result;
end;
$$;

revoke all on function public.staff_class_lesson_state(uuid, date) from public, anon;
revoke all on function public.staff_set_class_lesson_state(uuid, date, text) from public, anon;
revoke all on function public.staff_student_completed_learning_history(uuid, integer) from public, anon;
grant execute on function public.staff_class_lesson_state(uuid, date) to authenticated;
grant execute on function public.staff_set_class_lesson_state(uuid, date, text) to authenticated;
grant execute on function public.staff_student_completed_learning_history(uuid, integer) to authenticated;

notify pgrst, 'reload schema';