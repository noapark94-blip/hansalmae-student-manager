-- 한살매 학생관리 앱 1차 스키마
create extension if not exists pgcrypto;

create type public.user_role as enum ('admin', 'teacher', 'student', 'guardian');
create type public.enrollment_status as enum ('active', 'paused', 'completed');
create type public.attendance_status as enum ('present', 'late', 'absent', 'excused');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role public.user_role not null,
  display_name text not null,
  phone text,
  created_at timestamptz not null default now()
);

create table public.students (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid unique references public.profiles(id) on delete set null,
  name text not null,
  school text,
  grade text,
  phone text,
  status text not null default 'active',
  internal_note text,
  created_at timestamptz not null default now()
);

create table public.guardians (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid unique references public.profiles(id) on delete set null,
  name text not null,
  phone text not null,
  created_at timestamptz not null default now()
);

create table public.student_guardians (
  student_id uuid not null references public.students(id) on delete cascade,
  guardian_id uuid not null references public.guardians(id) on delete cascade,
  relationship text,
  is_primary boolean not null default false,
  primary key (student_id, guardian_id)
);

create table public.teachers (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid unique references public.profiles(id) on delete set null,
  name text not null,
  subject text,
  created_at timestamptz not null default now()
);

create table public.classes (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  subject text not null,
  teacher_id uuid references public.teachers(id) on delete set null,
  room text,
  color text not null default '#922D61',
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.class_schedules (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  weekday smallint not null check (weekday between 0 and 6),
  start_time time not null,
  end_time time not null,
  valid_from date,
  valid_until date
);

create table public.schedule_exceptions (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  original_date date not null,
  kind text not null check (kind in ('cancelled', 'changed', 'makeup')),
  replacement_date date,
  start_time time,
  end_time time,
  room text,
  note text
);

create table public.enrollments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  class_id uuid not null references public.classes(id) on delete cascade,
  status public.enrollment_status not null default 'active',
  started_on date not null default current_date,
  ended_on date,
  monthly_fee integer,
  unique (student_id, class_id, started_on)
);

create table public.lessons (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  lesson_date date not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  room text,
  status text not null default 'scheduled',
  unique (class_id, starts_at)
);

create table public.attendance (
  id uuid primary key default gen_random_uuid(),
  lesson_id uuid not null references public.lessons(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  status public.attendance_status not null,
  checked_at timestamptz,
  note text,
  makeup_required boolean not null default false,
  unique (lesson_id, student_id)
);

create table public.consultations (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  teacher_id uuid references public.teachers(id) on delete set null,
  consulted_at timestamptz not null default now(),
  internal_note text,
  guardian_summary text,
  student_summary text,
  next_contact_on date,
  created_at timestamptz not null default now()
);

create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  class_id uuid references public.classes(id) on delete cascade,
  author_profile_id uuid references public.profiles(id) on delete set null,
  title text not null,
  body text not null,
  audience text not null default 'class',
  published_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.message_logs (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.students(id) on delete set null,
  recipient_phone text not null,
  message_type text not null,
  body text not null,
  provider text,
  provider_message_id text,
  status text not null default 'queued',
  error_message text,
  sent_at timestamptz,
  created_at timestamptz not null default now()
);

create index attendance_student_idx on public.attendance(student_id);
create index lessons_date_idx on public.lessons(lesson_date);
create index enrollments_student_idx on public.enrollments(student_id, status);
create index consultations_student_date_idx on public.consultations(student_id, consulted_at desc);
create index message_logs_student_date_idx on public.message_logs(student_id, created_at desc);

alter table public.profiles enable row level security;
alter table public.students enable row level security;
alter table public.guardians enable row level security;
alter table public.student_guardians enable row level security;
alter table public.teachers enable row level security;
alter table public.classes enable row level security;
alter table public.class_schedules enable row level security;
alter table public.schedule_exceptions enable row level security;
alter table public.enrollments enable row level security;
alter table public.lessons enable row level security;
alter table public.attendance enable row level security;
alter table public.consultations enable row level security;
alter table public.announcements enable row level security;
alter table public.message_logs enable row level security;

-- 실제 운영 전 역할별 RLS 정책을 다음 마이그레이션에서 적용합니다.
-- 서비스 역할 키는 브라우저에 절대 노출하지 않습니다.
