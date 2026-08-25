create or replace function public.staff_delete_class_lesson_record(p_class_id uuid, p_date date)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then
    raise exception '교직원만 수업 기록을 삭제할 수 있습니다.';
  end if;
  if public.current_user_role() <> 'admin'
     and not exists (
       select 1 from public.class_teachers
       where class_id = p_class_id and profile_id = auth.uid()
     ) then
    raise exception '담당 클래스만 수정할 수 있습니다.';
  end if;

  delete from public.class_daily_notices
  where class_id = p_class_id and notice_date = p_date;

  delete from public.lessons
  where class_id = p_class_id and lesson_date = p_date;
end;
$$;

revoke all on function public.staff_delete_class_lesson_record(uuid,date) from public, anon;
grant execute on function public.staff_delete_class_lesson_record(uuid,date) to authenticated;

create or replace function public.staff_delete_special_lesson_record(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff() or not exists (
    select 1 from public.teacher_special_lessons l
    where l.id = p_session_id
      and (l.teacher_profile_id = auth.uid() or public.current_user_role() = 'admin')
  ) then
    raise exception '이 수업 기록을 삭제할 수 없습니다.';
  end if;

  delete from public.teacher_special_lesson_exam_results where session_id = p_session_id;
  delete from public.family_special_lesson_report_reads where session_id = p_session_id;

  update public.teacher_special_lesson_students
  set attendance_status = null,
      late_minutes = null,
      absence_reason = null,
      lesson_content = null,
      assigned_homework = null,
      inspection_status = null,
      inspection_note = null,
      updated_at = now()
  where session_id = p_session_id;

  update public.teacher_special_lessons
  set class_notice = null, status = 'draft', updated_at = now()
  where id = p_session_id;
end;
$$;

revoke all on function public.staff_delete_special_lesson_record(uuid) from public, anon;
grant execute on function public.staff_delete_special_lesson_record(uuid) to authenticated;

create or replace function public.staff_delete_correction_reports(p_records jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  assignment_id uuid;
  correction_date date;
  start_time time;
begin
  if not public.is_staff() then
    raise exception '교직원만 첨삭 기록을 삭제할 수 있습니다.';
  end if;

  for item in select value from jsonb_array_elements(coalesce(p_records, '[]'::jsonb))
  loop
    assignment_id := nullif(item->>'assignmentId','')::uuid;
    correction_date := nullif(item->>'date','')::date;
    start_time := nullif(item->>'startTime','')::time;

    if assignment_id is null or correction_date is null or start_time is null then
      raise exception '삭제할 첨삭 기록을 확인해 주세요.';
    end if;

    delete from public.correction_reports
    where correction_reports.assignment_id = staff_delete_correction_reports.assignment_id
      and correction_reports.correction_date = staff_delete_correction_reports.correction_date
      and correction_reports.start_time = staff_delete_correction_reports.start_time;
  end loop;
end;
$$;

revoke all on function public.staff_delete_correction_reports(jsonb) from public, anon;
grant execute on function public.staff_delete_correction_reports(jsonb) to authenticated;

notify pgrst, 'reload schema';