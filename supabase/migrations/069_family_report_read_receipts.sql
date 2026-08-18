-- 한살매 학습리포트 확인 기록: 기존 수업 데이터와 분리해 학생/학부모의 확인 여부만 저장합니다.

create table if not exists public.family_learning_report_reads (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  viewer_profile_id uuid not null references public.profiles(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  unique (lesson_id, student_id, viewer_profile_id)
);

create index if not exists family_learning_report_reads_student_idx
  on public.family_learning_report_reads(student_id, viewer_profile_id, viewed_at desc);

alter table public.family_learning_report_reads enable row level security;

create policy "family_read_own_report_receipts"
on public.family_learning_report_reads for select to authenticated
using (viewer_profile_id = auth.uid());

create or replace function public.family_learning_report_reads(p_student_id uuid)
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
  if viewer_role is null or viewer_role not in ('student','guardian') then
    raise exception '학생 또는 학부모 계정만 학습리포트 확인 상태를 볼 수 있습니다.';
  end if;

  if viewer_role = 'student' then
    select s.id into selected_id from public.students s where s.profile_id = auth.uid();
    if selected_id is null or selected_id <> p_student_id then
      raise exception '본인 학습리포트만 확인할 수 있습니다.';
    end if;
  else
    select s.id into selected_id
    from public.guardians g
    join public.student_guardians sg on sg.guardian_id = g.id
    join public.students s on s.id = sg.student_id
    where g.profile_id = auth.uid() and s.id = p_student_id;
    if selected_id is null then
      raise exception '연결된 자녀의 학습리포트만 확인할 수 있습니다.';
    end if;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'lessonId', r.lesson_id,
    'viewedAt', r.viewed_at
  ) order by r.viewed_at desc), '[]'::jsonb)
  into result
  from public.family_learning_report_reads r
  where r.student_id = selected_id and r.viewer_profile_id = auth.uid();

  return result;
end;
$$;

create or replace function public.mark_family_learning_report_read(p_student_id uuid, p_lesson_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = public
as $$
declare
  viewer_role public.user_role;
  selected_id uuid;
  result timestamptz;
begin
  viewer_role := public.current_user_role();
  if viewer_role is null or viewer_role not in ('student','guardian') then
    raise exception '학생 또는 학부모 계정만 학습리포트를 확인할 수 있습니다.';
  end if;

  if viewer_role = 'student' then
    select s.id into selected_id from public.students s where s.profile_id = auth.uid();
    if selected_id is null or selected_id <> p_student_id then
      raise exception '본인 학습리포트만 확인할 수 있습니다.';
    end if;
  else
    select s.id into selected_id
    from public.guardians g
    join public.student_guardians sg on sg.guardian_id = g.id
    join public.students s on s.id = sg.student_id
    where g.profile_id = auth.uid() and s.id = p_student_id;
    if selected_id is null then
      raise exception '연결된 자녀의 학습리포트만 확인할 수 있습니다.';
    end if;
  end if;

  if not exists (
    select 1
    from public.lessons l
    join public.enrollments e on e.class_id = l.class_id and e.student_id = selected_id
    where l.id = p_lesson_id
      and e.started_on <= l.lesson_date
      and (e.ended_on is null or e.ended_on >= l.lesson_date)
  ) then
    raise exception '확인할 수 없는 학습리포트입니다.';
  end if;

  insert into public.family_learning_report_reads(lesson_id, student_id, viewer_profile_id, viewed_at)
  values(p_lesson_id, selected_id, auth.uid(), now())
  on conflict(lesson_id, student_id, viewer_profile_id)
  do update set viewed_at = excluded.viewed_at
  returning viewed_at into result;

  return result;
end;
$$;

revoke all on function public.family_learning_report_reads(uuid), public.mark_family_learning_report_read(uuid, uuid) from public;
grant execute on function public.family_learning_report_reads(uuid), public.mark_family_learning_report_read(uuid, uuid) to authenticated;

notify pgrst, 'reload schema';
