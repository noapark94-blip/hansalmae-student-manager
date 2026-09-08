-- Keep edits to an already-completed class lesson private until staff publish them.

alter table public.lessons
  add column if not exists revision_draft jsonb,
  add column if not exists revision_saved_at timestamptz,
  add column if not exists revision_saved_by uuid references public.profiles(id) on delete set null;

create or replace function public.staff_class_revision_draft(p_class_id uuid, p_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  result jsonb;
begin
  if not public.is_staff() then
    raise exception '교직원만 수정 임시저장을 확인할 수 있습니다.';
  end if;
  if public.current_user_role() <> 'admin'
     and not exists (
       select 1 from public.class_teachers
       where class_id = p_class_id and profile_id = auth.uid()
     ) then
    raise exception '담당 클래스만 확인할 수 있습니다.';
  end if;

  select case
    when l.status = 'completed' and l.revision_draft is not null then
      jsonb_build_object(
        'payload', l.revision_draft,
        'savedAt', l.revision_saved_at,
        'savedBy', coalesce(p.display_name, '담당 선생님')
      )
    else null
  end
  into result
  from public.lessons l
  left join public.profiles p on p.id = l.revision_saved_by
  where l.class_id = p_class_id and l.lesson_date = p_date
  order by l.starts_at
  limit 1;

  return result;
end;
$$;

create or replace function public.staff_save_class_revision_draft(
  p_class_id uuid,
  p_date date,
  p_payload jsonb
)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lesson_id uuid;
  v_saved_at timestamptz := now();
begin
  if not public.is_staff() then
    raise exception '교직원만 수정 내용을 임시저장할 수 있습니다.';
  end if;
  if public.current_user_role() <> 'admin'
     and not exists (
       select 1 from public.class_teachers
       where class_id = p_class_id and profile_id = auth.uid()
     ) then
    raise exception '담당 클래스만 수정할 수 있습니다.';
  end if;
  if p_payload is null
     or jsonb_typeof(p_payload) <> 'object'
     or jsonb_typeof(coalesce(p_payload->'rows', 'null'::jsonb)) <> 'array' then
    raise exception '임시저장할 수업 내용을 확인해 주세요.';
  end if;

  select l.id into v_lesson_id
  from public.lessons l
  where l.class_id = p_class_id
    and l.lesson_date = p_date
    and l.status = 'completed'
  order by l.starts_at
  limit 1;

  if v_lesson_id is null then
    raise exception '완료된 수업만 수정 임시저장할 수 있습니다.';
  end if;

  update public.lessons
  set revision_draft = p_payload,
      revision_saved_at = v_saved_at,
      revision_saved_by = auth.uid()
  where id = v_lesson_id;

  return v_saved_at;
end;
$$;

create or replace function public.staff_publish_class_revision(
  p_class_id uuid,
  p_date date,
  p_payload jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lesson_id uuid;
  v_row jsonb;
  v_exam jsonb;
  v_student_id uuid;
  v_status text;
  v_late_minutes integer;
  v_absence_reason text;
  v_missing_names text;
  v_exam_payload jsonb;
  v_homework_payload jsonb;
begin
  if not public.is_staff() then
    raise exception '교직원만 수정 내용을 반영할 수 있습니다.';
  end if;
  if public.current_user_role() <> 'admin'
     and not exists (
       select 1 from public.class_teachers
       where class_id = p_class_id and profile_id = auth.uid()
     ) then
    raise exception '담당 클래스만 수정할 수 있습니다.';
  end if;
  if p_payload is null
     or jsonb_typeof(p_payload) <> 'object'
     or jsonb_typeof(coalesce(p_payload->'rows', 'null'::jsonb)) <> 'array' then
    raise exception '반영할 수업 내용을 확인해 주세요.';
  end if;

  select l.id into v_lesson_id
  from public.lessons l
  where l.class_id = p_class_id
    and l.lesson_date = p_date
    and l.status = 'completed'
  order by l.starts_at
  limit 1
  for update;

  if v_lesson_id is null then
    raise exception '완료된 수업의 수정 내용만 반영할 수 있습니다.';
  end if;

  select string_agg(s.name, ', ' order by s.name)
  into v_missing_names
  from public.students s
  where public.student_attends_class_on(s.id, p_class_id, p_date)
    and not exists (
      select 1
      from jsonb_array_elements(p_payload->'rows') as draft_rows(item)
      where nullif(item->>'studentId', '')::uuid = s.id
        and item->>'status' in ('present', 'late', 'absent')
    );

  if v_missing_names is not null then
    raise exception '출결 미입력 학생: %', v_missing_names;
  end if;

  for v_row in select value from jsonb_array_elements(p_payload->'rows')
  loop
    v_student_id := nullif(v_row->>'studentId', '')::uuid;
    if v_student_id is null
       or not public.student_attends_class_on(v_student_id, p_class_id, p_date) then
      raise exception '이 날짜의 수업 명단에 없는 학생이 포함되어 있습니다.';
    end if;

    v_status := v_row->>'status';
    v_late_minutes := nullif(v_row->>'lateMinutes', '')::integer;
    v_absence_reason := nullif(trim(v_row->>'absenceReason'), '');
    if v_status = 'late' and coalesce(v_late_minutes, 0) < 1 then
      raise exception '지각 시간을 입력해 주세요.';
    end if;
    if v_status = 'absent' and v_absence_reason is null then
      raise exception '결석 사유를 입력해 주세요.';
    end if;

    perform public.staff_save_class_attendance(
      p_class_id,
      p_date,
      v_student_id,
      v_status::public.attendance_status,
      case when v_status = 'late' then v_late_minutes else null end,
      case when v_status = 'absent' then v_absence_reason else null end,
      nullif(trim(v_row->>'note'), '')
    );

    v_exam := coalesce(v_row->'exam', '{}'::jsonb);
    if nullif(trim(v_exam->>'examType'), '') is null
       and nullif(trim(v_exam->>'examTitle'), '') is null
       and nullif(v_exam->>'score', '') is null
       and nullif(trim(v_exam->>'evaluation'), '') is null then
      delete from public.lesson_exam_results
      where lesson_id = v_lesson_id and student_id = v_student_id;
    end if;
  end loop;

  select coalesce(jsonb_agg(jsonb_build_object(
    'studentId', item->>'studentId',
    'exams', jsonb_build_array(coalesce(item->'exam', '{}'::jsonb))
  )), '[]'::jsonb)
  into v_exam_payload
  from jsonb_array_elements(p_payload->'rows') as draft_rows(item);

  select coalesce(jsonb_agg(jsonb_build_object(
    'studentId', item->>'studentId',
    'lessonContent', item->>'lessonContent',
    'assignedHomework', item->>'assignedHomework',
    'inspectionStatus', item->>'inspectionStatus',
    'inspectionNote', item->>'inspectionNote'
  )), '[]'::jsonb)
  into v_homework_payload
  from jsonb_array_elements(p_payload->'rows') as draft_rows(item);

  perform public.staff_save_class_exam_results(p_class_id, p_date, v_exam_payload);
  perform public.staff_save_class_homework_results(p_class_id, p_date, v_homework_payload);
  perform public.staff_save_class_daily_notice(p_class_id, p_date, coalesce(p_payload->>'notice', ''));
  perform public.staff_save_class_lesson_content(p_class_id, p_date, coalesce(p_payload->>'lessonContent', ''));

  update public.lessons
  set status = 'completed',
      revision_draft = null,
      revision_saved_at = null,
      revision_saved_by = null,
      updated_at = now()
  where id = v_lesson_id;
end;
$$;

revoke all on function public.staff_class_revision_draft(uuid,date) from public, anon;
revoke all on function public.staff_save_class_revision_draft(uuid,date,jsonb) from public, anon;
revoke all on function public.staff_publish_class_revision(uuid,date,jsonb) from public, anon;

grant execute on function public.staff_class_revision_draft(uuid,date) to authenticated;
grant execute on function public.staff_save_class_revision_draft(uuid,date,jsonb) to authenticated;
grant execute on function public.staff_publish_class_revision(uuid,date,jsonb) to authenticated;

notify pgrst, 'reload schema';
