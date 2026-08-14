-- Fix the special-lesson save RPC to use the existing teacher_special_lessons.kind column.
-- The table schema created in migration 064 names this column "kind".

create or replace function public.staff_save_teacher_special_lesson(
  p_id uuid,
  p_teacher_id uuid,
  p_date date,
  p_start_time time,
  p_end_time time,
  p_kind text,
  p_room text,
  p_note text,
  p_student_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_teacher uuid := coalesce(p_teacher_id, auth.uid());
begin
  if not public.is_staff()
     or (public.current_user_role() <> 'admin' and v_teacher <> auth.uid()) then
    raise exception '저장 권한이 없습니다.';
  end if;

  if p_kind not in ('makeup', 'additional') or p_end_time <= p_start_time then
    raise exception '수업 구분과 시간을 확인해 주세요.';
  end if;

  if coalesce(array_length(p_student_ids, 1), 0) = 0 then
    raise exception '학생을 한 명 이상 선택해 주세요.';
  end if;

  if p_id is null then
    insert into public.teacher_special_lessons(
      teacher_profile_id,
      lesson_date,
      starts_at,
      ends_at,
      kind,
      room,
      note
    )
    values(
      v_teacher,
      p_date,
      p_start_time,
      p_end_time,
      p_kind,
      nullif(trim(p_room), ''),
      nullif(trim(p_note), '')
    )
    returning id into v_id;
  else
    if not exists(
      select 1
      from public.teacher_special_lessons
      where id = p_id
        and (
          teacher_profile_id = auth.uid()
          or public.current_user_role() = 'admin'
        )
    ) then
      raise exception '수정 권한이 없습니다.';
    end if;

    update public.teacher_special_lessons
    set teacher_profile_id = v_teacher,
        lesson_date = p_date,
        starts_at = p_start_time,
        ends_at = p_end_time,
        kind = p_kind,
        room = nullif(trim(p_room), ''),
        note = nullif(trim(p_note), ''),
        updated_at = now()
    where id = p_id
    returning id into v_id;
  end if;

  delete from public.teacher_special_lesson_exam_results
  where session_id = v_id
    and not (student_id = any(p_student_ids));

  delete from public.teacher_special_lesson_students
  where session_id = v_id
    and not (student_id = any(p_student_ids));

  insert into public.teacher_special_lesson_students(session_id, student_id)
  select v_id, student_id
  from unnest(p_student_ids) student_id
  on conflict do nothing;

  return v_id;
end
$$;

revoke all on function public.staff_save_teacher_special_lesson(
  uuid, uuid, date, time, time, text, text, text, uuid[]
) from public;

grant execute on function public.staff_save_teacher_special_lesson(
  uuid, uuid, date, time, time, text, text, text, uuid[]
) to authenticated;

notify pgrst, 'reload schema';
