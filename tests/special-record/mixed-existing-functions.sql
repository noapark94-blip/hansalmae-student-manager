CREATE OR REPLACE FUNCTION public.staff_save_teacher_special_lesson(p_id uuid, p_teacher_id uuid, p_date date, p_start_time time without time zone, p_end_time time without time zone, p_kind text, p_room text, p_note text, p_student_ids uuid[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;
CREATE OR REPLACE FUNCTION public.staff_save_special_with_reminder(p_values jsonb, p_reminder_enabled boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid;v jsonb:=p_values;begin
 if not public.is_staff() then raise exception '저장 권한이 없습니다.';end if;
 v_id:=public.staff_save_teacher_special_lesson(nullif(v->>'p_id','')::uuid,nullif(v->>'p_teacher_id','')::uuid,(v->>'p_date')::date,(v->>'p_start_time')::time,(v->>'p_end_time')::time,v->>'p_kind',v->>'p_room',v->>'p_note',array(select value::uuid from jsonb_array_elements_text(v->'p_student_ids')),nullif(v->>'p_subject_id','')::uuid);
 update public.teacher_special_lessons set reminder_enabled=coalesce(p_reminder_enabled,false), reminder_recipient_ids=case when v ? 'p_reminder_recipient_ids' then array(select value::uuid from jsonb_array_elements_text(v->'p_reminder_recipient_ids')) else reminder_recipient_ids end where teacher_special_lessons.id=v_id;
 return v_id;end $function$;
CREATE OR REPLACE FUNCTION public.staff_set_special_lesson_state(p_session_id uuid, p_state text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare missing_names text;
begin
  if not public.is_staff() or not exists(
    select 1 from public.teacher_special_lessons l
    where l.id=p_session_id and (l.teacher_profile_id=auth.uid() or public.current_user_role()='admin')
  ) then raise exception '수업 완료 상태를 변경할 수 없습니다.'; end if;
  if p_state not in ('draft','completed') then raise exception '수업 상태를 확인해 주세요.'; end if;
  if p_state='completed' then
    select string_agg(s.name,', ' order by s.name) into missing_names
    from public.teacher_special_lesson_students a join public.students s on s.id=a.student_id
    where a.session_id=p_session_id and a.attendance_status is null;
    if missing_names is not null then raise exception '출결 미입력 학생: %',missing_names; end if;
  end if;
  update public.teacher_special_lessons set status=p_state,updated_at=now() where id=p_session_id;
  return p_state;
end $function$;
CREATE OR REPLACE FUNCTION public.staff_save_teacher_special_lesson(p_id uuid, p_teacher_id uuid, p_date date, p_start_time time without time zone, p_end_time time without time zone, p_kind text, p_room text, p_note text, p_student_ids uuid[], p_subject_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid; v_teacher uuid:=coalesce(p_teacher_id,auth.uid());
begin
  if not public.is_staff() or (public.current_user_role()<>'admin' and v_teacher<>auth.uid()) then raise exception '저장 권한이 없습니다.'; end if;
  if p_kind not in ('makeup','additional') or p_end_time<=p_start_time then raise exception '수업 구분과 시간을 확인해 주세요.'; end if;
  if not exists(select 1 from public.academy_subjects where id=p_subject_id and active) then raise exception '수업 과목을 선택해 주세요.'; end if;
  if coalesce(array_length(p_student_ids,1),0)=0 then raise exception '학생을 한 명 이상 선택해 주세요.'; end if;
  if p_id is null then
    insert into public.teacher_special_lessons(teacher_profile_id,lesson_date,starts_at,ends_at,kind,subject_id,room,note,created_by)
    values(v_teacher,p_date,p_start_time,p_end_time,p_kind,p_subject_id,nullif(trim(p_room),''),nullif(trim(p_note),''),auth.uid()) returning id into v_id;
  else
    update public.teacher_special_lessons set teacher_profile_id=v_teacher,lesson_date=p_date,starts_at=p_start_time,ends_at=p_end_time,
      kind=p_kind,subject_id=p_subject_id,room=nullif(trim(p_room),''),note=nullif(trim(p_note),''),updated_at=now()
    where id=p_id and (teacher_profile_id=auth.uid() or public.current_user_role()='admin') returning id into v_id;
    if v_id is null then raise exception '수정 권한이 없습니다.'; end if;
  end if;
  delete from public.teacher_special_lesson_exam_results where session_id=v_id and not(student_id=any(p_student_ids));
  delete from public.teacher_special_lesson_students where session_id=v_id and not(student_id=any(p_student_ids));
  insert into public.teacher_special_lesson_students(session_id,student_id) select v_id,student_id from unnest(p_student_ids) student_id on conflict do nothing;
  return v_id;
end $function$;
CREATE OR REPLACE FUNCTION public.student_date_conflict_message(p_student_id uuid, p_date date, p_start_time time without time zone, p_end_time time without time zone, p_exclude_special_id uuid DEFAULT NULL::uuid, p_exclude_makeup_id uuid DEFAULT NULL::uuid, p_exclude_source_makeup_id uuid DEFAULT NULL::uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare message text; day_no smallint:=extract(isodow from p_date)::smallint;
begin
  select c.name||' 정규수업 '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI') into message
  from public.enrollments e join public.class_schedules cs on cs.class_id=e.class_id and cs.weekday=day_no
  join public.classes c on c.id=e.class_id and c.active
  where e.student_id=p_student_id and e.status='active'
    and (cs.valid_from is null or cs.valid_from<=p_date) and (cs.valid_until is null or cs.valid_until>=p_date)
    and cs.start_time<p_end_time and cs.end_time>p_start_time
    and not exists(select 1 from public.schedule_exceptions x where x.class_id=cs.class_id and x.original_date=p_date and x.kind='cancelled')
  order by cs.start_time limit 1;
  if message is not null then return message; end if;

  select coalesce(a.subject,'첨삭')||' 첨삭 '||to_char(public.correction_time_start(a.start_time,a.slot_index),'HH24:MI')||'–'||to_char(public.correction_time_end(a.end_time,a.slot_index),'HH24:MI') into message
  from public.correction_assignments a
  where a.student_id=p_student_id and a.active and a.weekday=day_no and a.valid_from<=p_date and (a.valid_until is null or a.valid_until>=p_date)
    and public.correction_time_start(a.start_time,a.slot_index)<p_end_time and public.correction_time_end(a.end_time,a.slot_index)>p_start_time
    and not exists(select 1 from public.correction_schedule_exceptions x where x.assignment_id=a.id and x.original_date=p_date and x.kind in ('move','cancel'))
  order by public.correction_time_start(a.start_time,a.slot_index) limit 1;
  if message is not null then return message; end if;

  select coalesce(a.subject,'첨삭')||' 첨삭 일정변경 '||to_char(x.target_start_time,'HH24:MI')||'–'||to_char(x.target_end_time,'HH24:MI') into message
  from public.correction_schedule_exceptions x join public.correction_assignments a on a.id=x.assignment_id
  where a.student_id=p_student_id and x.kind in ('move','extra') and x.target_date=p_date
    and x.target_start_time<p_end_time and x.target_end_time>p_start_time
  order by x.target_start_time limit 1;
  if message is not null then return message; end if;

  select case when l.kind='makeup' then '개별 보강 ' else '추가수업 ' end||to_char(l.starts_at,'HH24:MI')||'–'||to_char(l.ends_at,'HH24:MI') into message
  from public.teacher_special_lesson_students ss join public.teacher_special_lessons l on l.id=ss.session_id
  where ss.student_id=p_student_id and l.id<>coalesce(p_exclude_special_id,'00000000-0000-0000-0000-000000000000'::uuid)
    and l.lesson_date=p_date and l.starts_at<p_end_time and l.ends_at>p_start_time
  order by l.starts_at limit 1;
  if message is not null then return message; end if;

  select '결석 보강 '||to_char(ms.scheduled_at at time zone 'Asia/Seoul','HH24:MI')||'–'||to_char(ms.ends_at at time zone 'Asia/Seoul','HH24:MI') into message
  from public.makeup_sessions ms join public.attendance at on at.id=ms.attendance_id
  where at.student_id=p_student_id and ms.status='scheduled'
    and ms.id<>coalesce(p_exclude_makeup_id,'00000000-0000-0000-0000-000000000000'::uuid)
    and (ms.scheduled_at at time zone 'Asia/Seoul')::date=p_date
    and (ms.scheduled_at at time zone 'Asia/Seoul')::time<p_end_time and (ms.ends_at at time zone 'Asia/Seoul')::time>p_start_time
  order by ms.scheduled_at limit 1;
  if message is not null then return message; end if;

  select '결석 보강 '||to_char(sm.scheduled_at at time zone 'Asia/Seoul','HH24:MI')||'–'||to_char(sm.ends_at at time zone 'Asia/Seoul','HH24:MI') into message
  from public.source_makeup_sessions sm
  where sm.student_id=p_student_id and sm.status='scheduled'
    and sm.id<>coalesce(p_exclude_source_makeup_id,'00000000-0000-0000-0000-000000000000'::uuid)
    and (sm.scheduled_at at time zone 'Asia/Seoul')::date=p_date
    and (sm.scheduled_at at time zone 'Asia/Seoul')::time<p_end_time and (sm.ends_at at time zone 'Asia/Seoul')::time>p_start_time
  order by sm.scheduled_at limit 1;
  return message;
end $function$;
CREATE OR REPLACE FUNCTION public.prevent_special_lesson_student_conflict()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare l public.teacher_special_lessons; student_name text; conflict text;
begin
  select * into l from public.teacher_special_lessons where id=new.session_id;
  select name into student_name from public.students where id=new.student_id;
  conflict:=public.student_date_conflict_message(new.student_id,l.lesson_date,l.starts_at,l.ends_at,l.id,null,null);
  if conflict is not null then raise exception '학생 시간 충돌: % · %와 겹칩니다.',student_name,conflict; end if;
  return new;
end $function$;
CREATE OR REPLACE FUNCTION public.prevent_special_lesson_time_conflict()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare row_item record; conflict text;
begin
  if new.lesson_date is not distinct from old.lesson_date and new.starts_at is not distinct from old.starts_at and new.ends_at is not distinct from old.ends_at then return new; end if;
  for row_item in select ss.student_id,s.name from public.teacher_special_lesson_students ss join public.students s on s.id=ss.student_id where ss.session_id=new.id loop
    conflict:=public.student_date_conflict_message(row_item.student_id,new.lesson_date,new.starts_at,new.ends_at,new.id,null,null);
    if conflict is not null then raise exception '학생 시간 충돌: % · %와 겹칩니다.',row_item.name,conflict; end if;
  end loop;
  return new;
end $function$;
