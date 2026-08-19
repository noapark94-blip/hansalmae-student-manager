-- 실제 클래스 수정 화면이 호출하는 staff_update_class_with_teachers의 ambiguous id 오류를 제거합니다.
-- bare id 별칭을 사용하지 않고 모든 컬럼/값에 명확한 이름을 부여합니다.

create or replace function public.staff_update_class_with_teachers(
  p_class_id uuid,
  p_name text,
  p_subject_id uuid,
  p_room text,
  p_color text,
  p_schedules jsonb,
  p_teacher_ids uuid[]
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  schedule_row jsonb;
  normalized_teacher_ids uuid[];
  subject_row public.academy_subjects%rowtype;
begin
  if not public.is_staff()
     or (
       public.current_user_role() <> 'admin'
       and not exists (
         select 1
         from public.class_teachers ct
         where ct.class_id = p_class_id
           and ct.profile_id = auth.uid()
       )
     ) then
    raise exception '담당 클래스만 수정할 수 있습니다.';
  end if;

  if nullif(trim(p_name), '') is null then
    raise exception '클래스 이름을 입력해 주세요.';
  end if;

  select array_agg(distinct teacher_input.teacher_id order by teacher_input.teacher_id)
    into normalized_teacher_ids
  from unnest(coalesce(p_teacher_ids, '{}'::uuid[])) as teacher_input(teacher_id);

  if coalesce(array_length(normalized_teacher_ids, 1), 0) = 0 then
    raise exception '담당 선생님을 한 명 이상 선택해 주세요.';
  end if;

  if public.current_user_role() <> 'admin'
     and not auth.uid() = any(normalized_teacher_ids) then
    raise exception '본인을 담당 선생님에서 제외할 수 없습니다.';
  end if;

  if exists (
    select 1
    from unnest(normalized_teacher_ids) as teacher_input(teacher_id)
    left join public.profiles p on p.id = teacher_input.teacher_id
    where p.id is null
       or p.role not in ('admin', 'teacher')
  ) then
    raise exception '선택한 담당 선생님 계정을 확인해 주세요.';
  end if;

  if coalesce(jsonb_typeof(p_schedules), '') <> 'array'
     or jsonb_array_length(p_schedules) = 0 then
    raise exception '수업 요일과 시간을 입력해 주세요.';
  end if;

  select s.*
    into subject_row
  from public.academy_subjects s
  where s.id = p_subject_id
    and s.active
  limit 1;

  if subject_row.id is null then
    raise exception '사용 가능한 과목을 선택해 주세요.';
  end if;

  if exists (
    select 1
    from public.classes c
    where c.id <> p_class_id
      and c.active
      and lower(regexp_replace(c.name, '\s+', '', 'g')) = lower(regexp_replace(trim(p_name), '\s+', '', 'g'))
  ) then
    raise exception '같은 이름의 클래스가 이미 있습니다.';
  end if;

  update public.classes c
  set name = trim(p_name),
      subject = subject_row.name,
      subject_id = subject_row.id,
      room = nullif(trim(p_room), ''),
      color = coalesce(nullif(trim(p_color), ''), '#922D61')
  where c.id = p_class_id;

  if not found then
    raise exception '클래스를 찾을 수 없습니다.';
  end if;

  delete from public.class_schedules cs
  where cs.class_id = p_class_id;

  delete from public.class_teachers ct
  where ct.class_id = p_class_id;

  insert into public.class_teachers(class_id, profile_id)
  select p_class_id, teacher_input.teacher_id
  from unnest(normalized_teacher_ids) as teacher_input(teacher_id);

  for schedule_row in
    select schedule_input.value
    from jsonb_array_elements(p_schedules) as schedule_input(value)
  loop
    if (schedule_row->>'weekday')::smallint not between 1 and 7 then
      raise exception '수업 요일을 확인해 주세요.';
    end if;

    if (schedule_row->>'startTime')::time >= (schedule_row->>'endTime')::time then
      raise exception '종료 시간은 시작 시간보다 늦어야 합니다.';
    end if;

    insert into public.class_schedules(class_id, weekday, start_time, end_time)
    values (
      p_class_id,
      (schedule_row->>'weekday')::smallint,
      (schedule_row->>'startTime')::time,
      (schedule_row->>'endTime')::time
    );
  end loop;
end
$$;

revoke all on function public.staff_update_class_with_teachers(uuid,text,uuid,text,text,jsonb,uuid[]) from public;
grant execute on function public.staff_update_class_with_teachers(uuid,text,uuid,text,text,jsonb,uuid[]) to authenticated;

notify pgrst, 'reload schema';
