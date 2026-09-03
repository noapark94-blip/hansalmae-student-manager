create or replace function public.correction_slot_assistant_board()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then
    raise exception '교직원만 담당 조교 시간표를 확인할 수 있습니다.';
  end if;

  return jsonb_build_object(
    'canManage', public.current_user_role() in ('admin', 'teacher', 'assistant'),
    'assistants', coalesce((
      select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.display_name) order by p.display_name)
      from public.profiles p
      where p.is_active and p.role::text = 'assistant'
    ), '[]'::jsonb),
    'assignments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'weekday', a.weekday,
        'startTime', to_char(a.start_time, 'HH24:MI'),
        'assistantId', a.assistant_profile_id,
        'assistantName', p.display_name
      ) order by a.weekday, a.start_time, p.display_name)
      from public.correction_slot_assistants a
      join public.profiles p on p.id = a.assistant_profile_id
      where p.is_active and p.role::text = 'assistant'
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.staff_save_correction_slot_assistants(p_assignments jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  selected_id uuid;
  selected_weekday smallint;
  selected_start time;
begin
  if public.current_user_role() not in ('admin', 'teacher', 'assistant') then
    raise exception '관리자·선생님·조교만 담당 조교를 배정할 수 있습니다.';
  end if;
  if jsonb_typeof(coalesce(p_assignments, '[]'::jsonb)) <> 'array' then
    raise exception '담당 조교 배정 형식을 확인해 주세요.';
  end if;

  delete from public.correction_slot_assistants
  where weekday between 1 and 7;

  for item in select value from jsonb_array_elements(coalesce(p_assignments, '[]'::jsonb)) loop
    selected_weekday := (item ->> 'weekday')::smallint;
    selected_start := (item ->> 'startTime')::time;
    selected_id := (item ->> 'assistantId')::uuid;

    if selected_weekday not between 1 and 7 then
      raise exception '첨삭 요일을 확인해 주세요.';
    end if;
    if not (
      (selected_weekday between 1 and 5 and selected_start in (time '14:30', time '16:00', time '17:30', time '19:00', time '20:30'))
      or (selected_weekday between 6 and 7 and selected_start in (time '09:30', time '11:00', time '12:30', time '14:00', time '15:30'))
    ) then
      raise exception '첨삭 시간대를 확인해 주세요.';
    end if;
    if not exists (
      select 1 from public.profiles p
      where p.id = selected_id and p.is_active and p.role::text = 'assistant'
    ) then
      raise exception '활성 조교 계정만 배정할 수 있습니다.';
    end if;

    insert into public.correction_slot_assistants(weekday, start_time, assistant_profile_id, created_by)
    values(selected_weekday, selected_start, selected_id, auth.uid())
    on conflict (weekday, start_time, assistant_profile_id) do nothing;
  end loop;
end;
$$;

revoke all on function public.correction_slot_assistant_board() from public, anon;
revoke all on function public.staff_save_correction_slot_assistants(jsonb) from public, anon;
grant execute on function public.correction_slot_assistant_board() to authenticated;
grant execute on function public.staff_save_correction_slot_assistants(jsonb) to authenticated;

notify pgrst, 'reload schema';
