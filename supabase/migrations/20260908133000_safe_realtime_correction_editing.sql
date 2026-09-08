-- Preserve the first correction recorder, track later editors, and merge only
-- explicitly changed fields so multiple staff members can edit safely.

alter table public.correction_reports
  add column if not exists last_edited_by uuid references public.profiles(id) on delete set null,
  add column if not exists last_edited_by_name text;

update public.correction_reports
set last_edited_by=recorded_by,
    last_edited_by_name=recorded_by_name
where last_edited_by is null and recorded_by is not null;

create or replace function public.staff_patch_correction_report_v3(
  p_assignment_id uuid,
  p_correction_date date,
  p_start_time time,
  p_end_time time,
  p_changes jsonb,
  p_base jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  a public.correction_assignments;
  current_row public.correction_reports;
  current_state jsonb;
  changes jsonb:=coalesce(p_changes,'{}'::jsonb);
  base jsonb:=coalesce(p_base,'{}'::jsonb);
  pname text;
  conflict_field text;
begin
  if not public.is_staff() then
    raise exception '교직원만 첨삭 기록을 저장할 수 있습니다.';
  end if;
  if jsonb_typeof(changes)<>'object' or jsonb_typeof(base)<>'object' then
    raise exception '첨삭 수정 내용을 확인해 주세요.';
  end if;
  if exists(
    select 1 from jsonb_object_keys(changes) key
    where key not in (
      'attendanceStatus','lateMinutes','absenceReason','teacherInstruction',
      'examTitle','examRange','examScore','examMaxScore','evaluation',
      'homeworkInstruction','homeworkStatus','homeworkNote','correctionContent',
      'correctionTaskStatus','correctionTaskFeedback','assistantFeedback',
      'nextPreparation','published'
    )
  ) then
    raise exception '지원하지 않는 첨삭 수정 항목이 포함되어 있습니다.';
  end if;

  select * into a
  from public.correction_assignments
  where id=p_assignment_id
    and valid_from<=p_correction_date
    and (valid_until is null or valid_until>=p_correction_date);
  if a.id is null then
    raise exception '선택한 날짜에 유효한 첨삭 배정을 찾을 수 없습니다.';
  end if;
  if p_start_time>=p_end_time then
    raise exception '첨삭 시간을 확인해 주세요.';
  end if;
  select display_name into pname from public.profiles where id=auth.uid();

  select * into current_row
  from public.correction_reports
  where assignment_id=p_assignment_id
    and correction_date=p_correction_date
    and start_time=p_start_time
  for update;

  if current_row.id is null then
    insert into public.correction_reports(
      assignment_id,student_id,correction_date,start_time,end_time,subject,
      attendance_status,late_minutes,absence_reason,teacher_instruction,
      exam_title,exam_range,exam_score,exam_max_score,evaluation,
      homework_instruction,homework_status,homework_note,correction_content,
      correction_task_status,correction_task_feedback,assistant_feedback,
      next_preparation,published,instruction_by,recorded_by,recorded_by_name,
      last_edited_by,last_edited_by_name
    ) values (
      a.id,a.student_id,p_correction_date,p_start_time,p_end_time,a.subject,
      coalesce(nullif(changes->>'attendanceStatus',''),'scheduled'),
      nullif(changes->>'lateMinutes','')::integer,
      nullif(trim(changes->>'absenceReason'),''),
      nullif(trim(changes->>'teacherInstruction'),''),
      nullif(trim(changes->>'examTitle'),''),
      nullif(trim(changes->>'examRange'),''),
      nullif(changes->>'examScore','')::numeric,
      coalesce(nullif(changes->>'examMaxScore','')::numeric,100),
      nullif(trim(changes->>'evaluation'),''),
      nullif(trim(changes->>'homeworkInstruction'),''),
      nullif(changes->>'homeworkStatus',''),
      nullif(trim(changes->>'homeworkNote'),''),
      nullif(trim(changes->>'correctionContent'),''),
      nullif(changes->>'correctionTaskStatus',''),
      nullif(trim(changes->>'correctionTaskFeedback'),''),
      nullif(trim(changes->>'assistantFeedback'),''),
      nullif(trim(changes->>'nextPreparation'),''),
      coalesce((changes->>'published')::boolean,false),
      case when nullif(trim(changes->>'teacherInstruction'),'') is null then null else auth.uid() end,
      auth.uid(),pname,auth.uid(),pname
    ) returning * into current_row;
  else
    current_state:=jsonb_build_object(
      'attendanceStatus',current_row.attendance_status,
      'lateMinutes',current_row.late_minutes,
      'absenceReason',coalesce(current_row.absence_reason,''),
      'teacherInstruction',coalesce(current_row.teacher_instruction,''),
      'examTitle',coalesce(current_row.exam_title,''),
      'examRange',coalesce(current_row.exam_range,''),
      'examScore',current_row.exam_score,
      'examMaxScore',coalesce(current_row.exam_max_score,100),
      'evaluation',coalesce(current_row.evaluation,''),
      'homeworkInstruction',coalesce(current_row.homework_instruction,''),
      'homeworkStatus',current_row.homework_status,
      'homeworkNote',coalesce(current_row.homework_note,''),
      'correctionContent',coalesce(current_row.correction_content,''),
      'correctionTaskStatus',current_row.correction_task_status,
      'correctionTaskFeedback',coalesce(current_row.correction_task_feedback,''),
      'assistantFeedback',coalesce(current_row.assistant_feedback,''),
      'nextPreparation',coalesce(current_row.next_preparation,''),
      'published',current_row.published
    );

    select key into conflict_field
    from jsonb_object_keys(changes) key
    where not (base ? key) or current_state->key is distinct from base->key
    limit 1;
    if conflict_field is not null then
      raise exception '다른 담당자가 먼저 같은 항목을 수정했습니다. 최신 내용을 확인한 뒤 다시 저장해 주세요.';
    end if;

    update public.correction_reports r set
      end_time=p_end_time,
      attendance_status=case when changes?'attendanceStatus' then coalesce(nullif(changes->>'attendanceStatus',''),'scheduled') else r.attendance_status end,
      late_minutes=case when changes?'lateMinutes' then nullif(changes->>'lateMinutes','')::integer else r.late_minutes end,
      absence_reason=case when changes?'absenceReason' then nullif(trim(changes->>'absenceReason'),'') else r.absence_reason end,
      teacher_instruction=case when changes?'teacherInstruction' then nullif(trim(changes->>'teacherInstruction'),'') else r.teacher_instruction end,
      exam_title=case when changes?'examTitle' then nullif(trim(changes->>'examTitle'),'') else r.exam_title end,
      exam_range=case when changes?'examRange' then nullif(trim(changes->>'examRange'),'') else r.exam_range end,
      exam_score=case when changes?'examScore' then nullif(changes->>'examScore','')::numeric else r.exam_score end,
      exam_max_score=case when changes?'examMaxScore' then coalesce(nullif(changes->>'examMaxScore','')::numeric,100) else r.exam_max_score end,
      evaluation=case when changes?'evaluation' then nullif(trim(changes->>'evaluation'),'') else r.evaluation end,
      homework_instruction=case when changes?'homeworkInstruction' then nullif(trim(changes->>'homeworkInstruction'),'') else r.homework_instruction end,
      homework_status=case when changes?'homeworkStatus' then nullif(changes->>'homeworkStatus','') else r.homework_status end,
      homework_note=case when changes?'homeworkNote' then nullif(trim(changes->>'homeworkNote'),'') else r.homework_note end,
      correction_content=case when changes?'correctionContent' then nullif(trim(changes->>'correctionContent'),'') else r.correction_content end,
      correction_task_status=case when changes?'correctionTaskStatus' then nullif(changes->>'correctionTaskStatus','') else r.correction_task_status end,
      correction_task_feedback=case when changes?'correctionTaskFeedback' then nullif(trim(changes->>'correctionTaskFeedback'),'') else r.correction_task_feedback end,
      assistant_feedback=case when changes?'assistantFeedback' then nullif(trim(changes->>'assistantFeedback'),'') else r.assistant_feedback end,
      next_preparation=case when changes?'nextPreparation' then nullif(trim(changes->>'nextPreparation'),'') else r.next_preparation end,
      published=case when changes?'published' then coalesce((changes->>'published')::boolean,false) else r.published end,
      instruction_by=case when changes?'teacherInstruction' and nullif(trim(changes->>'teacherInstruction'),'') is distinct from r.teacher_instruction then auth.uid() else r.instruction_by end,
      recorded_by=coalesce(r.recorded_by,auth.uid()),
      recorded_by_name=coalesce(r.recorded_by_name,pname),
      last_edited_by=auth.uid(),
      last_edited_by_name=pname,
      updated_at=now()
    where r.id=current_row.id
    returning * into current_row;
  end if;

  if current_row.attendance_status not in ('scheduled','present','late','absent') then
    raise exception '출석 상태를 확인해 주세요.';
  end if;
  if current_row.attendance_status='late' and coalesce(current_row.late_minutes,0)<1 then
    raise exception '지각 시간을 입력해 주세요.';
  end if;
  if current_row.attendance_status='absent' and nullif(trim(current_row.absence_reason),'') is null then
    raise exception '결석 사유를 입력해 주세요.';
  end if;
  if current_row.correction_task_status is not null
     and current_row.correction_task_status not in ('completed','partial','incomplete') then
    raise exception '첨삭 과제 수행 상태를 확인해 주세요.';
  end if;
  if current_row.exam_score is not null and (
    current_row.exam_score<0 or coalesce(current_row.exam_max_score,0)<=0
    or current_row.exam_score>current_row.exam_max_score
  ) then
    raise exception '첨삭 시험 점수를 확인해 주세요.';
  end if;

  return jsonb_build_object(
    'id',current_row.id,
    'attendanceStatus',current_row.attendance_status,
    'lateMinutes',current_row.late_minutes,
    'absenceReason',coalesce(current_row.absence_reason,''),
    'teacherInstruction',coalesce(current_row.teacher_instruction,''),
    'examTitle',coalesce(current_row.exam_title,''),
    'examRange',coalesce(current_row.exam_range,''),
    'examScore',current_row.exam_score,
    'examMaxScore',current_row.exam_max_score,
    'evaluation',coalesce(current_row.evaluation,''),
    'homeworkInstruction',coalesce(current_row.homework_instruction,''),
    'homeworkStatus',current_row.homework_status,
    'homeworkNote',coalesce(current_row.homework_note,''),
    'correctionContent',coalesce(current_row.correction_content,''),
    'correctionTaskStatus',current_row.correction_task_status,
    'correctionTaskFeedback',coalesce(current_row.correction_task_feedback,''),
    'assistantFeedback',coalesce(current_row.assistant_feedback,''),
    'nextPreparation',coalesce(current_row.next_preparation,''),
    'published',current_row.published,
    'recordedByName',current_row.recorded_by_name,
    'lastEditedByName',current_row.last_edited_by_name,
    'updatedAt',current_row.updated_at
  );
end;
$$;

create or replace function public.staff_correction_report(
  p_assignment_id uuid,p_date date,p_start_time time
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  if not public.is_staff() then raise exception '교직원만 확인할 수 있습니다.'; end if;
  return coalesce((
    select jsonb_build_object(
      'id',r.id,'attendanceStatus',r.attendance_status,'lateMinutes',r.late_minutes,
      'absenceReason',coalesce(r.absence_reason,''),'teacherInstruction',coalesce(r.teacher_instruction,''),
      'examTitle',coalesce(r.exam_title,''),'examRange',coalesce(r.exam_range,''),
      'examScore',r.exam_score,'examMaxScore',r.exam_max_score,'evaluation',coalesce(r.evaluation,''),
      'homeworkInstruction',coalesce(r.homework_instruction,''),'homeworkStatus',r.homework_status,
      'homeworkNote',coalesce(r.homework_note,''),'correctionContent',coalesce(r.correction_content,''),
      'correctionTaskStatus',r.correction_task_status,'correctionTaskFeedback',coalesce(r.correction_task_feedback,''),
      'assistantFeedback',coalesce(r.assistant_feedback,''),'nextPreparation',coalesce(r.next_preparation,''),
      'published',r.published,'recordedByName',r.recorded_by_name,
      'lastEditedByName',r.last_edited_by_name,'updatedAt',r.updated_at
    )
    from public.correction_reports r
    where r.assignment_id=p_assignment_id and r.correction_date=p_date and r.start_time=p_start_time
  ),'{}'::jsonb);
end;
$$;

do $$
begin
  if not exists(
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='correction_reports'
  ) then
    alter publication supabase_realtime add table public.correction_reports;
  end if;
end;
$$;

revoke all on function public.staff_patch_correction_report_v3(uuid,date,time,time,jsonb,jsonb) from public,anon;
grant execute on function public.staff_patch_correction_report_v3(uuid,date,time,time,jsonb,jsonb) to authenticated;
revoke all on function public.staff_correction_report(uuid,date,time) from public,anon;
grant execute on function public.staff_correction_report(uuid,date,time) to authenticated;

notify pgrst,'reload schema';
