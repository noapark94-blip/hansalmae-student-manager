-- 클래스 수정 저장 시 PostgreSQL이 bare `id` 참조를 모호하게 해석하는 문제를 제거합니다.
-- 기존 helper 함수 호출 대신 클래스/시간표 수정을 한 함수 안에서 명시적 alias로 처리합니다.

create or replace function public.staff_update_class_with_schedules(
  p_class_id uuid,
  p_name text,
  p_subject_id uuid,
  p_room text,
  p_color text,
  p_schedules jsonb
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  schedule_row jsonb;
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
      and lower(regexp_replace(c.name, '\s+', '', 'g')) =
          lower(regexp_replace(trim(p_name), '\s+', '', 'g'))
  ) then
    raise exception '같은 이름의 클래스가 이미 있습니다.';
  end if;

  if coalesce(jsonb_typeof(p_schedules), '') <> 'array'
     or jsonb_array_length(p_schedules) = 0 then
    raise exception '수업 요일과 시간을 한 개 이상 입력해 주세요.';
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

  for schedule_row in
    select j.value
    from jsonb_array_elements(p_schedules) as j(value)
  loop
    if (schedule_row->>'weekday')::smallint not between 1 and 7 then
      raise exception '수업 요일을 확인해 주세요.';
    end if;

    if (schedule_row->>'startTime')::time >= (schedule_row->>'endTime')::time then
      raise exception '종료 시간은 시작 시간보다 늦어야 합니다.';
    end if;

    insert into public.class_schedules(
      class_id,
      weekday,
      start_time,
      end_time
    ) values (
      p_class_id,
      (schedule_row->>'weekday')::smallint,
      (schedule_row->>'startTime')::time,
      (schedule_row->>'endTime')::time
    );
  end loop;
end
$$;

revoke all on function public.staff_update_class_with_schedules(uuid,text,uuid,text,text,jsonb) from public;
grant execute on function public.staff_update_class_with_schedules(uuid,text,uuid,text,text,jsonb) to authenticated;

notify pgrst, 'reload schema';
