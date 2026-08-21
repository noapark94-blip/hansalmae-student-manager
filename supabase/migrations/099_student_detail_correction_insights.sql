-- 학생 상세 허브에서 정규수업과 첨삭수업의 최근 기록을 함께 조회합니다.
create or replace function public.staff_student_detail_insights(p_student_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then
    raise exception '교직원만 학생 통합 기록을 확인할 수 있습니다.';
  end if;
  if not exists (select 1 from public.students where id = p_student_id) then
    raise exception '학생을 찾을 수 없습니다.';
  end if;

  return jsonb_build_object(
    'regularAttendance', jsonb_build_object(
      'attendanceTotal', (select count(*) from public.attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=p_student_id and l.lesson_date>=current_date-30),
      'present', (select count(*) from public.attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=p_student_id and l.lesson_date>=current_date-30 and a.status='present'),
      'late', (select count(*) from public.attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=p_student_id and l.lesson_date>=current_date-30 and a.status='late'),
      'absent', (select count(*) from public.attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=p_student_id and l.lesson_date>=current_date-30 and a.status in ('absent','excused'))
    ),
    'correctionAttendance', jsonb_build_object(
      'attendanceTotal', (select count(*) from public.correction_reports r where r.student_id=p_student_id and r.correction_date>=current_date-30 and r.attendance_status<>'scheduled'),
      'present', (select count(*) from public.correction_reports r where r.student_id=p_student_id and r.correction_date>=current_date-30 and r.attendance_status='present'),
      'late', (select count(*) from public.correction_reports r where r.student_id=p_student_id and r.correction_date>=current_date-30 and r.attendance_status='late'),
      'absent', (select count(*) from public.correction_reports r where r.student_id=p_student_id and r.correction_date>=current_date-30 and r.attendance_status='absent')
    ),
    'correctionAttendanceRecords', coalesce((
      select jsonb_agg(to_jsonb(q) order by q."lessonDate" desc,q."startTime" desc)
      from (
        select r.id,r.correction_date as "lessonDate",(r.subject||' 첨삭')::text as "className",r.subject,
          r.start_time as "startTime",r.attendance_status as status,
          case when r.attendance_status='late' and r.late_minutes is not null then r.late_minutes||'분 지각'
               when r.attendance_status='absent' then coalesce(nullif(r.absence_reason,''),'결석 사유 없음')
               else null end as note
        from public.correction_reports r
        where r.student_id=p_student_id and r.attendance_status<>'scheduled'
        order by r.correction_date desc,r.start_time desc limit 30
      ) q
    ),'[]'::jsonb),
    'correctionExams', coalesce((
      select jsonb_agg(to_jsonb(q) order by q."lessonDate",q.id)
      from (
        select r.id,r.correction_date as "lessonDate",(r.subject||' 첨삭')::text as "className",r.subject,
          case when coalesce(r.exam_range,'') like '[종류]%'
            then nullif(trim(replace(split_part(r.exam_range,E'\n',1),'[종류]','')),'')
            else '첨삭 시험' end as "examType",
          coalesce(r.exam_title,'') as "examTitle",r.exam_score as score,
          coalesce(nullif(r.exam_max_score,0),100) as "maxScore",
          round(r.exam_score*100.0/coalesce(nullif(r.exam_max_score,0),100),1) as percent,
          coalesce(r.evaluation,'') as evaluation
        from public.correction_reports r
        where r.student_id=p_student_id and r.exam_score is not null
        order by r.correction_date desc,r.created_at desc limit 50
      ) q
    ),'[]'::jsonb),
    'correctionLearning', coalesce((
      select jsonb_agg(to_jsonb(q) order by q."lessonDate" desc,q.id desc)
      from (
        select r.id,r.correction_date as "lessonDate",r.subject,
          coalesce(r.homework_instruction,'') as "homeworkInstruction",
          coalesce(r.homework_status,'') as "homeworkStatus",
          coalesce(r.homework_note,'') as "homeworkNote",
          coalesce(r.correction_content,'') as "correctionContent",
          coalesce(r.assistant_feedback,'') as "assistantFeedback"
        from public.correction_reports r
        where r.student_id=p_student_id and (
          nullif(trim(r.homework_instruction),'') is not null or
          nullif(trim(r.homework_note),'') is not null or
          nullif(trim(r.correction_content),'') is not null or
          nullif(trim(r.assistant_feedback),'') is not null
        )
        order by r.correction_date desc,r.created_at desc limit 20
      ) q
    ),'[]'::jsonb)
  );
end
$$;

revoke all on function public.staff_student_detail_insights(uuid) from public;
grant execute on function public.staff_student_detail_insights(uuid) to authenticated;
notify pgrst,'reload schema';
