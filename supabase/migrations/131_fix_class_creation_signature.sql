drop function if exists public.staff_create_class_with_schedules(text,uuid,text,text,jsonb,uuid);

create function public.staff_create_class_with_schedules(
  p_name text,
  p_subject_id uuid,
  p_room text,
  p_color text,
  p_schedules jsonb,
  p_teacher_ids uuid[]
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  result_id uuid;
  schedule_row jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 클래스를 만들 수 있습니다.'; end if;
  if coalesce(array_length(p_teacher_ids,1),0)=0 then raise exception '담당 선생님을 한 명 이상 선택해 주세요.'; end if;
  if public.current_user_role()<>'admin' and not (auth.uid()=any(p_teacher_ids)) then
    raise exception '본인이 포함된 담당 클래스로만 만들 수 있습니다.';
  end if;
  if exists(
    select 1 from unnest(p_teacher_ids) selected(id)
    left join public.profiles p on p.id=selected.id and p.is_active and p.role in ('admin','teacher','manager')
    where p.id is null
  ) then raise exception '사용 가능한 담당 선생님을 선택해 주세요.'; end if;
  if coalesce(jsonb_typeof(p_schedules),'')<>'array' or jsonb_array_length(p_schedules)=0 then
    raise exception '수업 요일과 시간을 한 개 이상 입력해 주세요.';
  end if;

  result_id:=public.staff_create_my_class(p_name,p_subject_id,p_room,p_color);
  delete from public.class_teachers where class_id=result_id;
  insert into public.class_teachers(class_id,profile_id)
  select result_id,id from unnest(p_teacher_ids) selected(id);

  for schedule_row in select value from jsonb_array_elements(p_schedules)
  loop
    perform public.staff_save_class_schedule(
      null,
      result_id,
      (schedule_row->>'weekday')::smallint,
      (schedule_row->>'start_time')::time,
      (schedule_row->>'end_time')::time,
      p_teacher_ids
    );
  end loop;
  return result_id;
end
$$;

revoke all on function public.staff_create_class_with_schedules(text,uuid,text,text,jsonb,uuid[]) from public;
grant execute on function public.staff_create_class_with_schedules(text,uuid,text,text,jsonb,uuid[]) to authenticated;
notify pgrst,'reload schema';
