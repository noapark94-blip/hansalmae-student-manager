-- 선생님 클래스 화면에서 학부모의 학습리포트 확인 여부를 조회합니다.

create or replace function public.staff_class_family_report_read_status(
  p_class_id uuid,
  p_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
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
$$;

revoke all on function public.staff_class_family_report_read_status(uuid, date) from public;
grant execute on function public.staff_class_family_report_read_status(uuid, date) to authenticated;

notify pgrst, 'reload schema';
