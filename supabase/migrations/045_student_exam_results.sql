create table public.lesson_exam_results (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  score numeric(7,2) check (score is null or score >= 0),
  max_score numeric(7,2) not null default 100 check (max_score > 0),
  evaluation text,
  feedback text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (lesson_id, student_id)
);

alter table public.lesson_exam_results enable row level security;
create policy "assigned_staff_read_exam_results" on public.lesson_exam_results for select to authenticated using (
  public.current_user_role() = 'admin' or exists (
    select 1 from public.lessons l join public.class_teachers ct on ct.class_id = l.class_id
    where l.id = lesson_id and ct.profile_id = auth.uid()
  )
);
create policy "assigned_staff_manage_exam_results" on public.lesson_exam_results for all to authenticated using (
  public.current_user_role() = 'admin' or exists (
    select 1 from public.lessons l join public.class_teachers ct on ct.class_id = l.class_id
    where l.id = lesson_id and ct.profile_id = auth.uid()
  )
) with check (
  public.current_user_role() = 'admin' or exists (
    select 1 from public.lessons l join public.class_teachers ct on ct.class_id = l.class_id
    where l.id = lesson_id and ct.profile_id = auth.uid()
  )
);

create or replace function public.staff_class_exam_results(p_class_id uuid, p_date date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not public.is_staff() then
    raise exception '교직원만 시험 결과를 확인할 수 있습니다.';
  end if;
  if public.current_user_role() <> 'admin' and not exists (
    select 1 from public.class_teachers where class_id = p_class_id and profile_id = auth.uid()
  ) then
    raise exception '담당 클래스의 시험 결과만 확인할 수 있습니다.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'studentId', s.id,
    'studentName', s.name,
    'school', s.school,
    'grade', s.grade,
    'score', r.score,
    'maxScore', coalesce(r.max_score, 100),
    'evaluation', coalesce(r.evaluation, ''),
    'feedback', coalesce(r.feedback, '')
  ) order by s.name), '[]'::jsonb)
  into v_result
  from public.enrollments e
  join public.students s on s.id = e.student_id
  left join lateral (
    select lesson.id from public.lessons lesson
    where lesson.class_id = p_class_id and lesson.lesson_date = p_date
    order by lesson.starts_at
    limit 1
  ) l on true
  left join public.lesson_exam_results r on r.lesson_id = l.id and r.student_id = s.id
  where e.class_id = p_class_id
    and e.status = 'active'
    and e.started_on <= p_date
    and (e.ended_on is null or e.ended_on >= p_date);

  return v_result;
end;
$$;

create or replace function public.staff_save_class_exam_results(p_class_id uuid, p_date date, p_results jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lesson_id uuid;
  v_item jsonb;
  v_student_id uuid;
  v_score numeric;
  v_max_score numeric;
  v_evaluation text;
  v_feedback text;
begin
  v_lesson_id := public.staff_save_class_day(p_class_id, p_date, null, null, null);

  for v_item in select value from jsonb_array_elements(coalesce(p_results, '[]'::jsonb))
  loop
    v_student_id := (v_item->>'studentId')::uuid;
    v_score := nullif(v_item->>'score', '')::numeric;
    v_max_score := coalesce(nullif(v_item->>'maxScore', '')::numeric, 100);
    v_evaluation := nullif(trim(v_item->>'evaluation'), '');
    v_feedback := nullif(trim(v_item->>'feedback'), '');

    if not exists (
      select 1 from public.enrollments
      where class_id = p_class_id and student_id = v_student_id and status = 'active'
        and started_on <= p_date and (ended_on is null or ended_on >= p_date)
    ) then
      raise exception '이 클래스의 수강생이 아닌 학생이 포함되어 있습니다.';
    end if;
    if v_score is not null and v_score < 0 then
      raise exception '점수는 0 이상이어야 합니다.';
    end if;
    if v_max_score <= 0 or (v_score is not null and v_score > v_max_score) then
      raise exception '점수와 만점을 확인해 주세요.';
    end if;

    if v_score is null and v_evaluation is null and v_feedback is null then
      delete from public.lesson_exam_results where lesson_id = v_lesson_id and student_id = v_student_id;
    else
      insert into public.lesson_exam_results(lesson_id, student_id, score, max_score, evaluation, feedback, created_by)
      values(v_lesson_id, v_student_id, v_score, v_max_score, v_evaluation, v_feedback, auth.uid())
      on conflict(lesson_id, student_id) do update set
        score = excluded.score,
        max_score = excluded.max_score,
        evaluation = excluded.evaluation,
        feedback = excluded.feedback,
        updated_at = now();
    end if;
  end loop;
end;
$$;

revoke all on function public.staff_class_exam_results(uuid, date), public.staff_save_class_exam_results(uuid, date, jsonb) from public;
grant execute on function public.staff_class_exam_results(uuid, date), public.staff_save_class_exam_results(uuid, date, jsonb) to authenticated;
