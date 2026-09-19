-- One class/date editor must read and write the same saved lesson after timetable changes.
-- Existing lessons, exams, attendance, homework and sent reports are never merged or deleted.
create or replace function public.internal_class_record_lesson_id(p_class_id uuid,p_date date)
returns uuid language sql stable security invoker set search_path=public as $$
 select id from public.lessons where class_id=p_class_id and lesson_date=p_date
 order by (status='completed') desc, (status='cancelled'), starts_at, id limit 1
$$;
revoke all on function public.internal_class_record_lesson_id(uuid,date) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.staff_class_lesson_state(p_class_id uuid, p_date date)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  and l.id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by l.starts_at
  limit 1;

  return coalesce(result, 'draft');
end;
$function$;

CREATE OR REPLACE FUNCTION public.staff_class_day(p_class_id uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 수업 기록을 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  select jsonb_build_object('lessonId',l.id,'examContent',null,'lessonContent',null,'homeworkContent',null,
    'students',coalesce((select jsonb_agg(jsonb_build_object(
      'id',s.id,'name',s.name,'school',s.school,'grade',s.grade,'status',a.status,
      'lateMinutes',a.late_minutes,'absenceReason',a.absence_reason,'note',a.note,
      'directAdded',exists(select 1 from public.class_lesson_roster_overrides o where o.class_id=p_class_id and o.lesson_date=p_date and o.student_id=s.id)
    ) order by s.name)
      from public.students s left join public.attendance a on a.student_id=s.id and a.lesson_id=l.id
      where public.student_attends_class_on(s.id,p_class_id,p_date)),'[]'::jsonb))
  into result from public.classes c left join lateral(select lesson.* from public.lessons lesson where lesson.class_id=c.id and lesson.lesson_date=p_date and lesson.id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by lesson.starts_at limit 1) l on true where c.id=p_class_id;
  return coalesce(result,jsonb_build_object('lessonId',null,'examContent',null,'lessonContent',null,'homeworkContent',null,'students','[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION public.staff_apply_class_revision_payload(p_class_id uuid, p_date date, p_payload jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  and l.id=public.internal_class_record_lesson_id(p_class_id,p_date)
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
$function$;

CREATE OR REPLACE FUNCTION public.staff_class_revision_draft(p_class_id uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
  if not public.is_staff() then
    raise exception '교직원만 수정 임시저장을 확인할 수 있습니다.';
  end if;
  if public.current_user_role()<>'admin'
     and not exists(
       select 1 from public.class_teachers
       where class_id=p_class_id and profile_id=auth.uid()
     ) then
    raise exception '담당 클래스만 확인할 수 있습니다.';
  end if;

  select jsonb_build_object(
    'payload',d.payload,
    'savedAt',d.saved_at,
    'savedBy',coalesce(p.display_name,'담당 선생님')
  )
  into result
  from public.lessons l
  join public.class_lesson_revision_drafts d on d.lesson_id=l.id
  left join public.profiles p on p.id=d.saved_by
  where l.class_id=p_class_id and l.lesson_date=p_date and l.status='completed'
  and l.id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by l.starts_at
  limit 1;

  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.staff_publish_class_revision(p_class_id uuid, p_date date, p_payload jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_lesson_id uuid;
begin
  perform public.staff_apply_class_revision_payload(p_class_id,p_date,p_payload);

  select id into v_lesson_id
  from public.lessons
  where class_id=p_class_id and lesson_date=p_date and status='completed'
  and id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by starts_at
  limit 1;

  delete from public.class_lesson_revision_drafts where lesson_id=v_lesson_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.staff_save_class_revision_draft(p_class_id uuid, p_date date, p_payload jsonb)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_lesson_id uuid; v_saved_at timestamptz:=now();
begin
  if not public.is_staff() then
    raise exception '교직원만 수정 내용을 임시저장할 수 있습니다.';
  end if;
  if public.current_user_role()<>'admin'
     and not exists(
       select 1 from public.class_teachers
       where class_id=p_class_id and profile_id=auth.uid()
     ) then
    raise exception '담당 클래스만 수정할 수 있습니다.';
  end if;
  if p_payload is null
     or jsonb_typeof(p_payload)<>'object'
     or jsonb_typeof(coalesce(p_payload->'rows','null'::jsonb))<>'array' then
    raise exception '임시저장할 수업 내용을 확인해 주세요.';
  end if;

  select id into v_lesson_id
  from public.lessons
  where class_id=p_class_id and lesson_date=p_date and status='completed'
  and id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by starts_at
  limit 1;
  if v_lesson_id is null then
    raise exception '완료된 수업만 수정 임시저장할 수 있습니다.';
  end if;

  insert into public.class_lesson_revision_drafts(lesson_id,payload,saved_at,saved_by)
  values(v_lesson_id,p_payload,v_saved_at,auth.uid())
  on conflict(lesson_id) do update
  set payload=excluded.payload,saved_at=excluded.saved_at,saved_by=excluded.saved_by;

  return v_saved_at;
end;
$function$;

CREATE OR REPLACE FUNCTION public.staff_clear_class_attendance(p_class_id uuid, p_date date, p_student_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_lesson_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 출결을 수정할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then
    raise exception '담당 클래스만 수정할 수 있습니다.';
  end if;
  select l.id into v_lesson_id from public.lessons l where l.class_id=p_class_id and l.lesson_date=p_date and l.id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by l.starts_at limit 1;
  if v_lesson_id is not null then delete from public.attendance a where a.lesson_id=v_lesson_id and a.student_id=p_student_id; end if;
end $function$;

CREATE OR REPLACE FUNCTION public.staff_class_family_report_read_status(p_class_id uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_lesson_id uuid;
  v_students jsonb;
  v_total integer := 0;
  v_linked integer := 0;
  v_confirmed integer := 0;
begin
  if not public.is_staff() then
    raise exception '교직원만 학부모 확인 현황을 볼 수 있습니다.';
  end if;

  if public.current_user_role() <> 'admin' and not exists (
    select 1
    from public.class_teachers ct
    where ct.class_id = p_class_id and ct.profile_id = auth.uid()
  ) then
    raise exception '담당 클래스의 확인 현황만 볼 수 있습니다.';
  end if;

  select l.id into v_lesson_id
  from public.lessons l
  where l.class_id = p_class_id and l.lesson_date = p_date
  and l.id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by l.starts_at
  limit 1;

  select
    count(*)::integer,
    count(*) filter (where guardian_count > 0)::integer,
    count(*) filter (where guardian_count > 0 and read_count > 0)::integer,
    coalesce(jsonb_agg(jsonb_build_object(
      'studentId', student_id,
      'studentName', student_name,
      'school', school,
      'grade', grade,
      'guardianCount', guardian_count,
      'readCount', read_count,
      'status', case
        when guardian_count = 0 then 'unlinked'
        when read_count > 0 then 'confirmed'
        else 'unconfirmed'
      end,
      'viewedAt', viewed_at
    ) order by student_name), '[]'::jsonb)
  into v_total, v_linked, v_confirmed, v_students
  from (
    select
      s.id as student_id,
      s.name as student_name,
      s.school,
      s.grade,
      (
        select count(distinct g.profile_id)::integer
        from public.student_guardians sg
        join public.guardians g on g.id = sg.guardian_id
        where sg.student_id = s.id and g.profile_id is not null
      ) as guardian_count,
      case when v_lesson_id is null then 0 else (
        select count(distinct r.viewer_profile_id)::integer
        from public.family_learning_report_reads r
        join public.guardians g on g.profile_id = r.viewer_profile_id
        join public.student_guardians sg on sg.guardian_id = g.id and sg.student_id = s.id
        where r.lesson_id = v_lesson_id and r.student_id = s.id
      ) end as read_count,
      case when v_lesson_id is null then null else (
        select max(r.viewed_at)
        from public.family_learning_report_reads r
        join public.guardians g on g.profile_id = r.viewer_profile_id
        join public.student_guardians sg on sg.guardian_id = g.id and sg.student_id = s.id
        where r.lesson_id = v_lesson_id and r.student_id = s.id
      ) end as viewed_at
    from public.enrollments e
    join public.students s on s.id = e.student_id
    where e.class_id = p_class_id
      and e.status = 'active'
      and e.started_on <= p_date
      and (e.ended_on is null or e.ended_on >= p_date)
      and public.student_attends_class_on(s.id, p_class_id, p_date)
  ) student_rows;

  return jsonb_build_object(
    'lessonId', v_lesson_id,
    'totalStudents', coalesce(v_total, 0),
    'linkedStudents', coalesce(v_linked, 0),
    'confirmedStudents', coalesce(v_confirmed, 0),
    'unconfirmedStudents', greatest(coalesce(v_linked, 0) - coalesce(v_confirmed, 0), 0),
    'unlinkedStudents', greatest(coalesce(v_total, 0) - coalesce(v_linked, 0), 0),
    'students', coalesce(v_students, '[]'::jsonb)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.staff_class_lesson_content(p_class_id uuid, p_date date)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_staff() then raise exception '교직원만 수업내용을 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers ct where ct.class_id=p_class_id and ct.profile_id=auth.uid()) then
    raise exception '담당 클래스만 확인할 수 있습니다.';
  end if;
  return coalesce((select l.lesson_content from public.lessons l where l.class_id=p_class_id and l.lesson_date=p_date and l.id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by l.starts_at limit 1),'');
end $function$;

CREATE OR REPLACE FUNCTION public.staff_delete_class_student_record(p_class_id uuid, p_date date, p_student_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_lesson_id uuid;
begin
  if not public.is_staff() then
    raise exception '교직원만 학생별 수업 기록을 삭제할 수 있습니다.';
  end if;
  if public.current_user_role()<>'admin'
     and not exists(
       select 1 from public.class_teachers
       where class_id=p_class_id and profile_id=auth.uid()
     ) then
    raise exception '담당 클래스만 수정할 수 있습니다.';
  end if;
  if not exists(select 1 from public.students where id=p_student_id) then
    raise exception '학생 정보를 찾을 수 없습니다.';
  end if;

  select id into v_lesson_id
  from public.lessons
  where class_id=p_class_id and lesson_date=p_date
  and id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by starts_at
  limit 1
  for update;

  if v_lesson_id is null then return; end if;

  delete from public.learning_report_comments
  where lesson_id=v_lesson_id and student_id=p_student_id;

  delete from public.family_learning_report_reads
  where lesson_id=v_lesson_id and student_id=p_student_id;

  delete from public.family_notifications
  where source_type='learning_report'
    and source_id=v_lesson_id
    and student_id=p_student_id;

  delete from public.lesson_exam_results
  where lesson_id=v_lesson_id and student_id=p_student_id;

  delete from public.lesson_homework_results
  where lesson_id=v_lesson_id and student_id=p_student_id;

  delete from public.attendance
  where lesson_id=v_lesson_id and student_id=p_student_id;

  update public.class_lesson_revision_drafts d
  set payload=jsonb_set(
    d.payload,
    '{rows}',
    coalesce((
      select jsonb_agg(entry.item order by entry.ordinality)
      from jsonb_array_elements(coalesce(d.payload->'rows','[]'::jsonb))
        with ordinality as entry(item,ordinality)
      where entry.item->>'studentId'<>p_student_id::text
    ),'[]'::jsonb),
    true
  ),
  saved_at=now(),
  saved_by=auth.uid()
  where d.lesson_id=v_lesson_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.staff_class_edit_snapshot(p_class_id uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ex jsonb; hw jsonb; dy jsonb; rv jsonb; nt text; lc text; payload jsonb; st text;
begin
 if auth.uid() is null or not public.is_staff() or
   (public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid())) then
  raise exception '담당 클래스만 확인할 수 있습니다.';
 end if;
 ex:=public.staff_class_exam_results(p_class_id,p_date);
 hw:=public.staff_class_homework_results(p_class_id,p_date);
 dy:=public.staff_class_day(p_class_id,p_date);
 rv:=public.staff_class_revision_draft(p_class_id,p_date);
 nt:=public.staff_class_daily_notice(p_class_id,p_date);
 lc:=public.staff_class_lesson_content(p_class_id,p_date);
 select case when status='completed' then 'completed' else 'draft' end into st from public.lessons
  where class_id=p_class_id and lesson_date=p_date and id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by starts_at limit 1;
 select jsonb_build_object('notice',coalesce(nt,''),'lessonContent',coalesce(lc,''),'rows',coalesce(jsonb_agg(
  s||jsonb_build_object('studentId',s->>'id','status',case when s->>'status'='excused' then to_jsonb('absent'::text) else s->'status' end,
   'lessonContent',h->>'lessonContent','assignedHomework',h->>'assignedHomework','inspectionStatus',h->>'inspectionStatus','inspectionNote',h->>'inspectionNote',
   'exam',coalesce(e->'exams'->0,'{}'))),'[]')) into payload
 from jsonb_array_elements(coalesce(dy->'students','[]')) s
 left join jsonb_array_elements(coalesce(ex,'[]')) e on e->>'studentId'=s->>'id'
 left join jsonb_array_elements(coalesce(hw,'[]')) h on h->>'studentId'=s->>'id';
 -- A private revision is a complete existing draft; keep its original display semantics.
 return jsonb_build_object('exams',ex,'homework',hw,'day',dy,'notice',nt,'lessonContent',lc,'revision',rv,
  'state',coalesce(st,'draft'),'values',public.class_edit_values(coalesce(rv->'payload',payload)));
end $function$;

CREATE OR REPLACE FUNCTION public.staff_patch_class_record(p_class_id uuid, p_date date, p_changes jsonb, p_expected_state text, p_mode text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare snap jsonb; current_values jsonb; merged jsonb; payload jsonb; r record; row_value jsonb; row_payload jsonb;
 rows_payload jsonb:='[]'; exams jsonb:='[]'; homework jsonb:='[]'; lesson_id uuid; before_row jsonb; k text; change_exam boolean; change_hw boolean;
begin
 if auth.uid() is null or not public.is_staff() or
   (public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid())) then
  raise exception '담당 클래스만 수정할 수 있습니다.';
 end if;
 if p_mode not in ('draft','complete','revision','publish','attendance') or p_mode is null then raise exception '저장 방식을 확인해 주세요.'; end if;
 -- Serialize only this class/date, including the first save when no lesson row exists.
 perform pg_advisory_xact_lock(hashtextextended(p_class_id::text||':'||p_date::text,0));
 select id into lesson_id from public.lessons where class_id=p_class_id and lesson_date=p_date and id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by starts_at limit 1 for update;
 snap:=public.staff_class_edit_snapshot(p_class_id,p_date);
 if snap->>'state' is distinct from p_expected_state then raise exception '수업 완료 상태가 변경됐습니다. 입력 내용을 보관한 뒤 최신 기록을 확인해 주세요.'; end if;
 if (p_mode in ('revision','publish'))<>(p_expected_state='completed') then raise exception '수업 상태에 맞는 저장 버튼을 이용해 주세요.'; end if;
 current_values:=snap->'values';
 merged:=public.class_merge_edit_changes(current_values,p_changes);
 -- Identity is a dependency when changing an exam, not a user-editable field.
 if exists(select 1 from jsonb_array_elements(p_changes) c where c->'path'->>2='exam_id' and c->'before' is distinct from c->'value') then raise exception '시험 기록 식별자는 수정할 수 없습니다.'; end if;
 if p_mode='attendance' and exists(select 1 from jsonb_array_elements(p_changes) c where jsonb_array_length(c->'path')<>3 or c->'path'->>2 not in ('status','lateMinutes','absenceReason','note')) then raise exception '출결 항목만 저장할 수 있습니다.'; end if;
 for r in select * from jsonb_each(merged->'students') loop
  row_value:=r.value; before_row:=current_values->'students'->r.key;
  row_payload:=jsonb_build_object('studentId',r.key,'status',row_value->'status','lateMinutes',row_value->'lateMinutes',
   'absenceReason',row_value->>'absenceReason','note',row_value->>'note','lessonContent',row_value->>'lessonContent',
   'assignedHomework',row_value->>'assignedHomework','inspectionStatus',row_value->>'inspectionStatus','inspectionNote',row_value->>'inspectionNote',
   'exam',jsonb_build_object('id',nullif(row_value->>'exam_id',''),'examType',row_value->>'exam_examType','examTitle',row_value->>'exam_examTitle',
    'score',nullif(row_value->>'exam_score','')::numeric,'maxScore',coalesce(nullif(row_value->>'exam_maxScore','')::numeric,100),'evaluation',row_value->>'exam_evaluation','feedback',row_value->>'exam_feedback'));
  rows_payload:=rows_payload||jsonb_build_array(row_payload);
  if p_mode in ('revision','publish') or row_value=before_row then continue; end if;
  change_exam:=false; change_hw:=false;
  foreach k in array array['exam_examType','exam_examTitle','exam_score','exam_maxScore','exam_evaluation'] loop
   change_exam:=change_exam or row_value->k is distinct from before_row->k;
  end loop;
  foreach k in array array['lessonContent','assignedHomework','inspectionStatus','inspectionNote'] loop
   change_hw:=change_hw or row_value->k is distinct from before_row->k;
  end loop;
  if change_exam then exams:=exams||jsonb_build_array(jsonb_build_object('studentId',r.key,'exams',jsonb_build_array(row_payload->'exam'))); end if;
  if change_hw then homework:=homework||jsonb_build_array(row_payload-'exam'); end if;
  if row_value->'status' is distinct from before_row->'status' or row_value->'lateMinutes' is distinct from before_row->'lateMinutes'
    or row_value->'absenceReason' is distinct from before_row->'absenceReason' or row_value->'note' is distinct from before_row->'note' then
   if row_value->>'status' is null then perform public.staff_clear_class_attendance(p_class_id,p_date,r.key::uuid);
   else perform public.staff_save_class_attendance(p_class_id,p_date,r.key::uuid,(row_value->>'status')::public.attendance_status,
    nullif(row_value->>'lateMinutes','')::integer,nullif(row_value->>'absenceReason',''),nullif(row_value->>'note','')); end if;
  end if;
 end loop;
 payload:=jsonb_build_object('notice',merged->>'notice','lessonContent',merged->>'lessonContent','rows',rows_payload);
 if p_mode='revision' then perform public.staff_save_class_revision_draft(p_class_id,p_date,payload);
 elsif p_mode='publish' then perform public.staff_publish_class_revision(p_class_id,p_date,payload);
 else
  if jsonb_array_length(exams)>0 then perform public.staff_save_class_exam_results(p_class_id,p_date,exams); end if;
  if jsonb_array_length(homework)>0 then perform public.staff_save_class_homework_results(p_class_id,p_date,homework); end if;
  if merged->'notice' is distinct from current_values->'notice' then perform public.staff_save_class_daily_notice(p_class_id,p_date,merged->>'notice'); end if;
  if merged->'lessonContent' is distinct from current_values->'lessonContent' then perform public.staff_save_class_lesson_content(p_class_id,p_date,merged->>'lessonContent'); end if;
  if p_mode<>'attendance' then perform public.staff_set_class_lesson_state(p_class_id,p_date,case when p_mode='complete' then 'completed' else 'draft' end); end if;
 end if;
 return public.staff_class_edit_snapshot(p_class_id,p_date);
end $function$;

CREATE OR REPLACE FUNCTION public.staff_class_exam_results(p_class_id uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 시험 결과를 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'studentId',s.id,'studentName',s.name,'school',s.school,'grade',s.grade,
    'exams',coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'examType',coalesce(r.exam_type,''),'examTitle',coalesce(r.exam_title,''),'score',r.score,'maxScore',coalesce(r.max_score,100),'evaluation',coalesce(r.evaluation,''),'feedback',coalesce(r.feedback,'')) order by r.created_at,r.id) from public.lesson_exam_results r where r.lesson_id=l.id and r.student_id=s.id),'[]'::jsonb)
  ) order by s.name),'[]'::jsonb) into result
  from public.students s
  left join lateral(select lesson.id from public.lessons lesson where lesson.class_id=p_class_id and lesson.lesson_date=p_date and lesson.id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by lesson.starts_at limit 1) l on true
  where public.student_attends_class_on(s.id,p_class_id,p_date);
  return result;
end $function$;

CREATE OR REPLACE FUNCTION public.staff_class_homework_results(p_class_id uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 숙제 결과를 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('studentId',s.id,'lessonContent',coalesce(current_result.lesson_content,''),'assignedHomework',coalesce(current_result.assigned_homework,''),'inspectionStatus',coalesce(current_result.inspection_status,current_result.status,''),'inspectionNote',coalesce(current_result.inspection_note,current_result.note,''),'previousHomework',coalesce(previous_result.assigned_homework,'')) order by s.name),'[]'::jsonb) into result
  from public.students s
  left join lateral(select id from public.lessons where class_id=p_class_id and lesson_date=p_date and id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by starts_at limit 1) lesson on true
  left join public.lesson_homework_results current_result on current_result.lesson_id=lesson.id and current_result.student_id=s.id
  left join lateral(select hr.assigned_homework from public.lesson_homework_results hr join public.lessons prior on prior.id=hr.lesson_id where prior.class_id=p_class_id and prior.lesson_date<p_date and hr.student_id=s.id and nullif(trim(hr.assigned_homework),'') is not null order by prior.lesson_date desc limit 1) previous_result on true
  where public.student_attends_class_on(s.id,p_class_id,p_date);
  return result;
end $function$;

create or replace function public.staff_save_class_day(p_class_id uuid,p_date date,p_exam_content text,p_lesson_content text,p_homework_content text)
returns uuid language plpgsql security definer set search_path=public as $$
declare schedule_row public.class_schedules; result_id uuid; v_start time; v_end time;
begin
  if not public.is_staff() then raise exception '교직원만 수업 기록을 저장할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 수정할 수 있습니다.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_class_id::text||':'||p_date::text,0));
  select id into result_id from public.lessons
  where id=public.internal_class_record_lesson_id(p_class_id,p_date) for update;
  if result_id is not null then return result_id; end if;
  select * into schedule_row from public.class_schedules where class_id=p_class_id and weekday=extract(isodow from p_date)::smallint and (valid_from is null or valid_from<=p_date) and (valid_until is null or valid_until>=p_date) order by start_time limit 1;
  if schedule_row.id is null and not exists(select 1 from public.class_makeup_attendees where class_id=p_class_id and attendance_date=p_date) then raise exception '정규 수업이 없는 날짜입니다. 보충 학생을 먼저 추가해 주세요.'; end if;
  v_start:=coalesce(schedule_row.start_time,'18:00'::time); v_end:=coalesce(schedule_row.end_time,'20:00'::time);
  insert into public.lessons(class_id,lesson_date,starts_at,ends_at,room,teacher_profile_id,updated_at)
  select c.id,p_date,((p_date+v_start) at time zone 'Asia/Seoul'),((p_date+v_end) at time zone 'Asia/Seoul'),c.room,auth.uid(),now() from public.classes c where c.id=p_class_id
  on conflict(class_id,starts_at) do update set teacher_profile_id=auth.uid(),updated_at=now()
  returning id into result_id;
  return result_id;
end $$;
