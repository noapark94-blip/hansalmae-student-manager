create or replace function public.staff_create_class_with_schedules(
  p_name text,
  p_subject_id uuid,
  p_room text,
  p_color text,
  p_schedules jsonb,
  p_teacher_id uuid
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  result_id uuid;
  schedule_row jsonb;
  target_teacher uuid;
begin
  if not public.is_staff() then raise exception '교직원만 클래스를 만들 수 있습니다.'; end if;
  target_teacher := auth.uid();
  if p_teacher_id is distinct from target_teacher and public.current_user_role()<>'admin' then
    raise exception '본인 담당 클래스로만 만들 수 있습니다.';
  end if;
  if coalesce(jsonb_typeof(p_schedules),'')<>'array' or jsonb_array_length(p_schedules)=0 then
    raise exception '수업 요일과 시간을 한 개 이상 입력해 주세요.';
  end if;

  result_id := public.staff_create_my_class(p_name,p_subject_id,p_room,p_color);
  if p_teacher_id is not null and p_teacher_id<>target_teacher and public.current_user_role()='admin' then
    delete from public.class_teachers where class_id=result_id;
    insert into public.class_teachers(class_id,profile_id) values(result_id,p_teacher_id);
    target_teacher := p_teacher_id;
  end if;

  for schedule_row in select value from jsonb_array_elements(p_schedules)
  loop
    perform public.staff_save_class_schedule(
      null,
      result_id,
      (schedule_row->>'weekday')::smallint,
      (schedule_row->>'startTime')::time,
      (schedule_row->>'endTime')::time,
      array[target_teacher]::uuid[]
    );
  end loop;
  return result_id;
end
$$;

revoke all on function public.staff_create_class_with_schedules(text,uuid,text,text,jsonb,uuid) from public;
grant execute on function public.staff_create_class_with_schedules(text,uuid,text,text,jsonb,uuid) to authenticated;
notify pgrst,'reload schema';
