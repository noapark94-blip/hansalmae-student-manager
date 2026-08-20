-- 빈 보강일 해제 및 의미 없는 빈 기록 제외

create or replace function public.staff_clear_empty_class_makeup_day(
  p_class_id uuid,
  p_date date
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then
    raise exception '교직원만 보강 수업을 해제할 수 있습니다.';
  end if;

  if public.current_user_role() <> 'admin'
     and not exists (
       select 1 from public.class_teachers
       where class_id = p_class_id and profile_id = auth.uid()
     ) then
    raise exception '담당 클래스만 관리할 수 있습니다.';
  end if;

  if not exists (
    select 1 from public.class_makeup_attendees
    where class_id = p_class_id and attendance_date = p_date
  ) then
    return;
  end if;

  if exists (
    select 1
    from public.lessons l
    where l.class_id = p_class_id
      and l.lesson_date = p_date
      and (
        nullif(trim(l.lesson_content), '') is not null
        or nullif(trim(l.homework_content), '') is not null
        or nullif(trim(l.exam_content), '') is not null
        or exists (select 1 from public.attendance a where a.lesson_id = l.id)
        or exists (
          select 1 from public.lesson_homework_results hr
          where hr.lesson_id = l.id
            and (
              nullif(trim(coalesce(hr.status, '')), '') is not null
              or nullif(trim(coalesce(hr.note, '')), '') is not null
              or nullif(trim(coalesce(hr.assigned_homework, '')), '') is not null
              or nullif(trim(coalesce(hr.inspection_status, '')), '') is not null
              or nullif(trim(coalesce(hr.inspection_note, '')), '') is not null
            )
        )
        or exists (
          select 1 from public.lesson_exam_results er
          where er.lesson_id = l.id
            and (
              er.score is not null
              or nullif(trim(coalesce(er.exam_type, '')), '') is not null
              or nullif(trim(coalesce(er.exam_title, '')), '') is not null
              or nullif(trim(coalesce(er.evaluation, '')), '') is not null
              or nullif(trim(coalesce(er.feedback, '')), '') is not null
            )
        )
      )
  ) or exists (
    select 1 from public.class_daily_notices n
    where n.class_id = p_class_id
      and n.notice_date = p_date
      and nullif(trim(n.content), '') is not null
  ) then
    raise exception '이미 입력된 수업 기록이 있어 보강 수업을 해제할 수 없습니다. 기록을 먼저 비워 주세요.';
  end if;

  delete from public.class_makeup_attendees
  where class_id = p_class_id and attendance_date = p_date;
end;
$$;

revoke all on function public.staff_clear_empty_class_makeup_day(uuid, date) from public, anon;
grant execute on function public.staff_clear_empty_class_makeup_day(uuid, date) to authenticated;

create or replace function public.staff_student_learning_history(
  p_student_id uuid,
  p_limit integer default 300
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  viewer_role public.user_role;
  safe_limit integer;
  result jsonb;
begin
  viewer_role := public.current_user_role();
  if viewer_role is null or viewer_role not in ('admin','teacher') then
    raise exception '교직원 계정만 학생 수업 기록을 확인할 수 있습니다.';
  end if;
  if p_student_id is null then return '[]'::jsonb; end if;
  safe_limit := greatest(1, least(coalesce(p_limit, 300), 500));

  select coalesce(jsonb_agg(report_row order by lesson_date desc, starts_at desc), '[]'::jsonb)
  into result
  from (
    select jsonb_build_object(
      'lessonId', l.id,
      'lessonDate', to_char(l.lesson_date, 'YYYY-MM-DD'),
      'startsAt', l.starts_at,
      'classId', c.id,
      'className', c.name,
      'subject', c.subject,
      'room', coalesce(l.room, c.room),
      'teacherName', coalesce(tp.display_name, '담당 선생님'),
      'lessonContent', coalesce(l.lesson_content, ''),
      'homeworkContent', coalesce(nullif(trim(hr.assigned_homework), ''), nullif(trim(l.homework_content), ''), ''),
      'examContent', coalesce(l.exam_content, ''),
      'attendance', case when a.id is null then null else jsonb_build_object(
        'status', a.status,
        'lateMinutes', a.late_minutes,
        'absenceReason', coalesce(a.absence_reason, ''),
        'note', coalesce(a.note, '')
      ) end,
      'homeworkResult', case
        when hr.id is null or (
          nullif(trim(coalesce(hr.status, '')), '') is null
          and nullif(trim(coalesce(hr.note, '')), '') is null
          and nullif(trim(coalesce(hr.inspection_status, '')), '') is null
          and nullif(trim(coalesce(hr.inspection_note, '')), '') is null
        ) then null
        else jsonb_build_object(
          'status', coalesce(nullif(hr.inspection_status, ''), hr.status, ''),
          'note', coalesce(nullif(hr.inspection_note, ''), hr.note, '')
        )
      end,
      'exams', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', er.id,
          'examType', coalesce(er.exam_type, ''),
          'examTitle', coalesce(er.exam_title, ''),
          'score', er.score,
          'maxScore', coalesce(er.max_score, 100),
          'percent', case when er.score is null or coalesce(er.max_score, 0) <= 0 then null else round(er.score / er.max_score * 100, 1) end,
          'evaluation', coalesce(er.evaluation, ''),
          'feedback', coalesce(er.feedback, '')
        ) order by er.created_at, er.id)
        from public.lesson_exam_results er
        where er.lesson_id = l.id
          and er.student_id = p_student_id
          and (
            er.score is not null
            or nullif(trim(coalesce(er.exam_type, '')), '') is not null
            or nullif(trim(coalesce(er.exam_title, '')), '') is not null
            or nullif(trim(coalesce(er.evaluation, '')), '') is not null
            or nullif(trim(coalesce(er.feedback, '')), '') is not null
          )
      ), '[]'::jsonb)
    ) as report_row, l.lesson_date, l.starts_at
    from public.lessons l
    join public.classes c on c.id = l.class_id
    join public.enrollments e on e.class_id = c.id and e.student_id = p_student_id
    left join public.profiles tp on tp.id = l.teacher_profile_id
    left join public.attendance a on a.lesson_id = l.id and a.student_id = p_student_id
    left join public.lesson_homework_results hr on hr.lesson_id = l.id and hr.student_id = p_student_id
    where e.started_on <= l.lesson_date
      and (e.ended_on is null or e.ended_on >= l.lesson_date)
      and l.lesson_date <= current_date
      and (
        a.id is not null
        or nullif(trim(l.lesson_content), '') is not null
        or nullif(trim(l.homework_content), '') is not null
        or nullif(trim(l.exam_content), '') is not null
        or (
          hr.id is not null and (
            nullif(trim(coalesce(hr.status, '')), '') is not null
            or nullif(trim(coalesce(hr.note, '')), '') is not null
            or nullif(trim(coalesce(hr.assigned_homework, '')), '') is not null
            or nullif(trim(coalesce(hr.inspection_status, '')), '') is not null
            or nullif(trim(coalesce(hr.inspection_note, '')), '') is not null
          )
        )
        or exists (
          select 1 from public.lesson_exam_results er
          where er.lesson_id = l.id
            and er.student_id = p_student_id
            and (
              er.score is not null
              or nullif(trim(coalesce(er.exam_type, '')), '') is not null
              or nullif(trim(coalesce(er.exam_title, '')), '') is not null
              or nullif(trim(coalesce(er.evaluation, '')), '') is not null
              or nullif(trim(coalesce(er.feedback, '')), '') is not null
            )
        )
      )
    order by l.lesson_date desc, l.starts_at desc
    limit safe_limit
  ) reports;
  return result;
end;
$$;

revoke all on function public.staff_student_learning_history(uuid, integer) from public, anon;
grant execute on function public.staff_student_learning_history(uuid, integer) to authenticated;

notify pgrst, 'reload schema';