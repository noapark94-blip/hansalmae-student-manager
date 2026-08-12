create or replace function public.family_exam_progress(p_student_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role public.user_role;
  v_student_id uuid;
  v_result jsonb;
begin
  v_role := public.current_user_role();
  if v_role not in ('student', 'guardian') then
    raise exception '학생 또는 학부모 계정만 시험 결과를 확인할 수 있습니다.';
  end if;

  if v_role = 'student' then
    select s.id into v_student_id from public.students s where s.profile_id = auth.uid();
    if p_student_id is not null and p_student_id <> v_student_id then
      raise exception '본인의 시험 결과만 확인할 수 있습니다.';
    end if;
  else
    select s.id into v_student_id
    from public.guardians g
    join public.student_guardians sg on sg.guardian_id = g.id
    join public.students s on s.id = sg.student_id
    where g.profile_id = auth.uid() and (p_student_id is null or s.id = p_student_id)
    order by sg.is_primary desc, s.name
    limit 1;
    if p_student_id is not null and v_student_id is null then
      raise exception '연결된 자녀의 시험 결과만 확인할 수 있습니다.';
    end if;
  end if;

  select coalesce(jsonb_agg(row_data order by lesson_date desc, created_at desc), '[]'::jsonb)
  into v_result
  from (
    select
      r.created_at,
      l.lesson_date,
      jsonb_build_object(
        'id', r.id,
        'lessonDate', l.lesson_date,
        'className', c.name,
        'subject', coalesce(subject.name, c.subject),
        'mainSubject', coalesce(subject.main_subject, c.subject),
        'examTitle', l.exam_content,
        'score', r.score,
        'maxScore', r.max_score,
        'percent', case when r.score is null then null else round(r.score / r.max_score * 100, 1) end,
        'evaluation', r.evaluation,
        'feedback', r.feedback,
        'teacherName', coalesce(p.display_name, '담당 선생님')
      ) as row_data
    from public.lesson_exam_results r
    join public.lessons l on l.id = r.lesson_id
    join public.classes c on c.id = l.class_id
    left join public.academy_subjects subject on subject.id = c.subject_id
    left join public.profiles p on p.id = coalesce(r.created_by, l.teacher_profile_id)
    where r.student_id = v_student_id
      and (r.score is not null or r.evaluation is not null or r.feedback is not null)
    order by l.lesson_date desc, r.created_at desc
    limit 60
  ) exam_rows;

  return v_result;
end;
$$;

revoke all on function public.family_exam_progress(uuid) from public;
grant execute on function public.family_exam_progress(uuid) to authenticated;
