-- 클래스 과제, 학생별 제출 상태, 첨삭 피드백과 가족 조회를 연결합니다.

create type public.assignment_submission_status as enum ('pending', 'submitted', 'reviewed');

create table public.assignments (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  title text not null,
  description text,
  due_at timestamptz not null,
  created_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table public.assignment_submissions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  status public.assignment_submission_status not null default 'pending',
  submitted_at timestamptz,
  feedback text,
  reviewed_at timestamptz,
  reviewed_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique (assignment_id, student_id)
);

alter table public.assignments enable row level security;
alter table public.assignment_submissions enable row level security;

create policy "staff_manage_assignments" on public.assignments for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "family_read_assignments" on public.assignments for select to authenticated using (
  exists (
    select 1 from public.enrollments e join public.students s on s.id = e.student_id
    where e.class_id = assignments.class_id and e.status = 'active' and s.profile_id = auth.uid()
  ) or exists (
    select 1 from public.enrollments e
    join public.student_guardians sg on sg.student_id = e.student_id
    join public.guardians g on g.id = sg.guardian_id
    where e.class_id = assignments.class_id and e.status = 'active' and g.profile_id = auth.uid()
  )
);
create policy "staff_manage_assignment_submissions" on public.assignment_submissions for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "family_read_assignment_submissions" on public.assignment_submissions for select to authenticated using (
  exists (select 1 from public.students s where s.id = student_id and s.profile_id = auth.uid())
  or exists (
    select 1 from public.student_guardians sg join public.guardians g on g.id = sg.guardian_id
    where sg.student_id = assignment_submissions.student_id and g.profile_id = auth.uid()
  )
);

grant select, insert, update, delete on table public.assignments, public.assignment_submissions to authenticated;

create or replace function public.assignment_board()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'isStaff', public.is_staff(),
    'classes', case when public.is_staff() then coalesce((
      select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by c.name)
      from public.classes c where c.active
    ), '[]'::jsonb) else '[]'::jsonb end,
    'assignments', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', a.id,
        'classId', c.id,
        'className', c.name,
        'title', a.title,
        'description', a.description,
        'dueAt', a.due_at,
        'createdAt', a.created_at,
        'students', coalesce((
          select jsonb_agg(jsonb_build_object(
            'studentId', s.id,
            'studentName', s.name,
            'status', coalesce(sub.status, 'pending'::public.assignment_submission_status),
            'submittedAt', sub.submitted_at,
            'feedback', sub.feedback,
            'reviewedAt', sub.reviewed_at
          ) order by s.name)
          from public.enrollments e
          join public.students s on s.id = e.student_id
          left join public.assignment_submissions sub on sub.assignment_id = a.id and sub.student_id = s.id
          where e.class_id = a.class_id and e.status = 'active'
            and (public.is_staff() or s.profile_id = auth.uid() or exists (
              select 1 from public.student_guardians sg join public.guardians g on g.id = sg.guardian_id
              where sg.student_id = s.id and g.profile_id = auth.uid()
            ))
        ), '[]'::jsonb)
      ) order by a.due_at desc)
      from public.assignments a join public.classes c on c.id = a.class_id
      where public.is_staff() or exists (
        select 1 from public.enrollments e join public.students s on s.id = e.student_id
        where e.class_id = a.class_id and e.status = 'active' and (
          s.profile_id = auth.uid() or exists (
            select 1 from public.student_guardians sg join public.guardians g on g.id = sg.guardian_id
            where sg.student_id = s.id and g.profile_id = auth.uid()
          )
        )
      )
    ), '[]'::jsonb)
  )
$$;

create or replace function public.staff_create_assignment(p_class_id uuid, p_title text, p_description text, p_due_at timestamptz)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare saved_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 과제를 등록할 수 있습니다.'; end if;
  if nullif(trim(p_title), '') is null then raise exception '과제 제목을 입력해 주세요.'; end if;
  if not exists (select 1 from public.classes c where c.id = p_class_id and c.active) then raise exception '운영 중인 클래스를 선택해 주세요.'; end if;
  insert into public.assignments(class_id, title, description, due_at, created_by)
  values (p_class_id, trim(p_title), nullif(trim(p_description), ''), p_due_at, auth.uid()) returning id into saved_id;
  return saved_id;
end
$$;

create or replace function public.staff_set_assignment_submission(
  p_assignment_id uuid,
  p_student_id uuid,
  p_status public.assignment_submission_status,
  p_feedback text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then raise exception '교직원만 제출과 첨삭 상태를 변경할 수 있습니다.'; end if;
  if not exists (
    select 1 from public.assignments a join public.enrollments e on e.class_id = a.class_id
    where a.id = p_assignment_id and e.student_id = p_student_id and e.status = 'active'
  ) then raise exception '이 과제의 수강 학생을 찾을 수 없습니다.'; end if;

  insert into public.assignment_submissions(assignment_id, student_id, status, submitted_at, feedback, reviewed_at, reviewed_by, updated_at)
  values (
    p_assignment_id, p_student_id, p_status,
    case when p_status in ('submitted', 'reviewed') then now() else null end,
    case when p_status = 'reviewed' then nullif(trim(p_feedback), '') else null end,
    case when p_status = 'reviewed' then now() else null end,
    case when p_status = 'reviewed' then auth.uid() else null end,
    now()
  )
  on conflict (assignment_id, student_id) do update set
    status = excluded.status,
    submitted_at = case when excluded.status = 'pending' then null else coalesce(assignment_submissions.submitted_at, excluded.submitted_at) end,
    feedback = excluded.feedback,
    reviewed_at = excluded.reviewed_at,
    reviewed_by = excluded.reviewed_by,
    updated_at = now();
end
$$;

create or replace function public.staff_delete_assignment(p_assignment_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then raise exception '교직원만 과제를 삭제할 수 있습니다.'; end if;
  delete from public.assignments where id = p_assignment_id;
  if not found then raise exception '과제를 찾을 수 없습니다.'; end if;
end
$$;

create or replace function public.assignment_dashboard_count()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case when public.is_staff() then jsonb_build_object(
    'unsubmitted', count(*) filter (where coalesce(sub.status, 'pending'::public.assignment_submission_status) = 'pending'),
    'reviewPending', count(*) filter (where sub.status = 'submitted'),
    'total', count(*) filter (where coalesce(sub.status, 'pending'::public.assignment_submission_status) in ('pending', 'submitted'))
  ) else jsonb_build_object('unsubmitted', 0, 'reviewPending', 0, 'total', 0) end
  from public.assignments a
  join public.enrollments e on e.class_id = a.class_id and e.status = 'active'
  left join public.assignment_submissions sub on sub.assignment_id = a.id and sub.student_id = e.student_id
$$;

revoke all on function public.assignment_board() from public;
revoke all on function public.staff_create_assignment(uuid, text, text, timestamptz) from public;
revoke all on function public.staff_set_assignment_submission(uuid, uuid, public.assignment_submission_status, text) from public;
revoke all on function public.staff_delete_assignment(uuid) from public;
revoke all on function public.assignment_dashboard_count() from public;
grant execute on function public.assignment_board() to authenticated;
grant execute on function public.staff_create_assignment(uuid, text, text, timestamptz) to authenticated;
grant execute on function public.staff_set_assignment_submission(uuid, uuid, public.assignment_submission_status, text) to authenticated;
grant execute on function public.staff_delete_assignment(uuid) to authenticated;
grant execute on function public.assignment_dashboard_count() to authenticated;
