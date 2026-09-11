create or replace function public.staff_correction_reports(p_records jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  record_count integer;
begin
  if not public.is_staff() then
    raise exception '교직원만 확인할 수 있습니다.';
  end if;

  if p_records is null or jsonb_typeof(p_records) <> 'array' then
    raise exception '첨삭 기록 목록 형식이 올바르지 않습니다.';
  end if;

  record_count := jsonb_array_length(p_records);
  if record_count > 500 then
    raise exception '한 번에 최대 500개의 첨삭 기록을 확인할 수 있습니다.';
  end if;

  return coalesce((
    select jsonb_agg(
      case
        when report.id is null then '{}'::jsonb
        else jsonb_build_object(
          'id',report.id,
          'attendanceStatus',report.attendance_status,
          'lateMinutes',report.late_minutes,
          'absenceReason',coalesce(report.absence_reason,''),
          'teacherInstruction',coalesce(report.teacher_instruction,''),
          'examTitle',coalesce(report.exam_title,''),
          'examRange',coalesce(report.exam_range,''),
          'examScore',report.exam_score,
          'examMaxScore',report.exam_max_score,
          'evaluation',coalesce(report.evaluation,''),
          'homeworkInstruction',coalesce(report.homework_instruction,''),
          'homeworkStatus',report.homework_status,
          'homeworkNote',coalesce(report.homework_note,''),
          'correctionContent',coalesce(report.correction_content,''),
          'correctionTaskStatus',report.correction_task_status,
          'correctionTaskFeedback',coalesce(report.correction_task_feedback,''),
          'assistantFeedback',coalesce(report.assistant_feedback,''),
          'nextPreparation',coalesce(report.next_preparation,''),
          'published',report.published,
          'recordedByName',report.recorded_by_name,
          'lastEditedByName',report.last_edited_by_name,
          'updatedAt',report.updated_at
        )
      end
      order by requested.ordinality
    )
    from jsonb_array_elements(p_records) with ordinality as requested(item, ordinality)
    left join public.correction_reports report
      on report.assignment_id=(requested.item->>'assignmentId')::uuid
      and report.correction_date=(requested.item->>'date')::date
      and report.start_time=(requested.item->>'startTime')::time
  ),'[]'::jsonb);
end;
$$;

revoke all on function public.staff_correction_reports(jsonb) from public,anon;
grant execute on function public.staff_correction_reports(jsonb) to authenticated;

notify pgrst,'reload schema';
