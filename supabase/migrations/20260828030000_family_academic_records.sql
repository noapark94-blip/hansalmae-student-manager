-- 학부모·학생이 데스크톱에서 입력한 내신/모의고사 성적을 안전하게 조회합니다.

create or replace function public.family_academic_records(p_student_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  viewer_role public.user_role;
  selected_id uuid;
  result jsonb;
begin
  viewer_role := public.current_user_role();
  if viewer_role not in ('student','guardian') then
    raise exception '학생 또는 학부모 계정만 성적을 확인할 수 있습니다.';
  end if;

  if viewer_role = 'student' then
    select s.id into selected_id from public.students s where s.profile_id = auth.uid();
    if p_student_id is not null and p_student_id <> selected_id then
      raise exception '본인의 성적만 확인할 수 있습니다.';
    end if;
  else
    select s.id into selected_id
    from public.guardians g
    join public.student_guardians sg on sg.guardian_id = g.id
    join public.students s on s.id = sg.student_id
    where g.profile_id = auth.uid()
      and (p_student_id is null or s.id = p_student_id)
    order by sg.is_primary desc, s.name
    limit 1;
    if p_student_id is not null and selected_id is null then
      raise exception '연결된 자녀의 성적만 확인할 수 있습니다.';
    end if;
  end if;

  select jsonb_build_object(
    'student', (select jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade) from public.students s where s.id=selected_id),
    'records', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',r.id,'recordType',r.record_type,'academicYear',r.academic_year,'semester',r.semester,
        'examDate',r.exam_date,'examName',r.exam_name,'subject',r.subject,'score',r.score,
        'grade',r.grade,'achievementLevel',r.achievement_level,'rank',r.rank,'cohortSize',r.cohort_size,
        'schoolAverage',r.school_average,'standardScore',r.standard_score,'percentile',r.percentile,'note',r.note
      ) order by r.exam_date desc, r.created_at desc)
      from public.student_academic_records r where r.student_id=selected_id
    ),'[]'::jsonb)
  ) into result;
  return result;
end;
$$;

revoke all on function public.family_academic_records(uuid) from public, anon;
grant execute on function public.family_academic_records(uuid) to authenticated;
