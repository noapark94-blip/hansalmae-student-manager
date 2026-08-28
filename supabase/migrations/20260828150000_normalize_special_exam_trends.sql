-- 보강·추가수업은 수업 종류이며 과목이 아니다. 실제 등록 과목을 성적 추이에 반환한다.
-- 기존 성적 데이터는 변경하지 않고 조회 결과만 바로잡는다.
create or replace function public.staff_student_special_lesson_insights(p_student_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
begin
  if not public.is_staff() then raise exception '교직원만 학생 통합 기록을 확인할 수 있습니다.'; end if;
  if not exists(select 1 from public.students where id=p_student_id) then raise exception '학생을 찾을 수 없습니다.'; end if;
  return jsonb_build_object(
    'attendance',jsonb_build_object(
      'attendanceTotal',(select count(*) from public.teacher_special_lesson_students a join public.teacher_special_lessons l on l.id=a.session_id where a.student_id=p_student_id and l.lesson_date>=current_date-30 and a.attendance_status is not null),
      'present',(select count(*) from public.teacher_special_lesson_students a join public.teacher_special_lessons l on l.id=a.session_id where a.student_id=p_student_id and l.lesson_date>=current_date-30 and a.attendance_status='present'),
      'late',(select count(*) from public.teacher_special_lesson_students a join public.teacher_special_lessons l on l.id=a.session_id where a.student_id=p_student_id and l.lesson_date>=current_date-30 and a.attendance_status='late'),
      'absent',(select count(*) from public.teacher_special_lesson_students a join public.teacher_special_lessons l on l.id=a.session_id where a.student_id=p_student_id and l.lesson_date>=current_date-30 and a.attendance_status='absent')
    ),
    'upcomingMakeups',(select count(*) from public.teacher_special_lesson_students a join public.teacher_special_lessons l on l.id=a.session_id where a.student_id=p_student_id and l.kind='makeup' and l.lesson_date>=current_date),
    'exams',coalesce((select jsonb_agg(to_jsonb(q) order by q."lessonDate",q.id) from (
      select e.id,l.lesson_date as "lessonDate",case when l.kind='makeup' then '개별 보강' else '추가수업' end as "className",
        coalesce(subject.name,subject.main_subject,'과목 미지정') as subject,
        coalesce(e.exam_type,'') as "examType",coalesce(e.exam_title,'') as "examTitle",
        e.score,coalesce(e.max_score,100) as "maxScore",
        case when e.score is null then null else round(e.score*100.0/coalesce(nullif(e.max_score,0),100),1) end as percent,
        coalesce(e.evaluation,'') as evaluation
      from public.teacher_special_lesson_exam_results e
      join public.teacher_special_lessons l on l.id=e.session_id
      left join public.academy_subjects subject on subject.id=l.subject_id
      where e.student_id=p_student_id and l.status='completed' and e.score is not null
      order by l.lesson_date desc,e.created_at desc limit 100
    ) q),'[]'::jsonb)
  );
end $$;

revoke all on function public.staff_student_special_lesson_insights(uuid) from public,anon;
grant execute on function public.staff_student_special_lesson_insights(uuid) to authenticated;
notify pgrst,'reload schema';
