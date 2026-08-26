-- 학생 상세의 내신·모의고사 성적을 학원 수업 시험 기록과 분리해 관리합니다.

create table public.student_academic_records (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  record_type text not null check (record_type in ('school','mock')),
  academic_year smallint not null check (academic_year between 2000 and 2100),
  semester smallint check (semester in (1,2)),
  exam_date date not null,
  exam_name text not null check (char_length(trim(exam_name)) between 1 and 40),
  subject text not null check (char_length(trim(subject)) between 1 and 40),
  score numeric(6,2) check (score between 0 and 100),
  grade smallint check (grade between 1 and 9),
  rank integer check (rank > 0),
  cohort_size integer check (cohort_size > 0),
  school_average numeric(6,2) check (school_average between 0 and 100),
  standard_score numeric(7,2) check (standard_score >= 0),
  percentile numeric(5,2) check (percentile between 0 and 100),
  note text,
  created_by uuid not null default auth.uid() references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (record_type <> 'school' or semester is not null),
  check (rank is null or cohort_size is null or rank <= cohort_size),
  check (
    (record_type = 'school' and num_nonnulls(score, grade, rank) > 0)
    or (record_type = 'mock' and num_nonnulls(score, standard_score, percentile, grade) > 0)
  )
);

create index student_academic_records_student_date_idx
  on public.student_academic_records(student_id, exam_date desc, created_at desc);
create index student_academic_records_created_by_idx
  on public.student_academic_records(created_by);

alter table public.student_academic_records enable row level security;

create policy student_academic_records_staff_select
on public.student_academic_records for select to authenticated
using (public.current_user_role() in ('admin','teacher','manager'));

create policy student_academic_records_staff_insert
on public.student_academic_records for insert to authenticated
with check (
  public.current_user_role() in ('admin','teacher','manager')
  and created_by = (select auth.uid())
);

create policy student_academic_records_staff_update
on public.student_academic_records for update to authenticated
using (public.current_user_role() in ('admin','teacher','manager'))
with check (public.current_user_role() in ('admin','teacher','manager'));

create policy student_academic_records_staff_delete
on public.student_academic_records for delete to authenticated
using (public.current_user_role() in ('admin','teacher','manager'));

grant select, insert, update, delete on public.student_academic_records to authenticated;
