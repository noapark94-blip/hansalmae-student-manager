-- 결석 출결과 연결된 보강 예약·완료·가족 확인 기능을 추가합니다.

create type public.makeup_status as enum ('scheduled', 'completed', 'cancelled');

create table public.makeup_sessions (
  id uuid primary key default gen_random_uuid(),
  attendance_id uuid not null unique references public.attendance(id) on delete cascade,
  teacher_profile_id uuid not null references public.profiles(id) on delete restrict,
  scheduled_at timestamptz not null,
  ends_at timestamptz not null,
  room text not null,
  status public.makeup_status not null default 'scheduled',
  note text,
  created_at timestamptz not null default now(),
  check (ends_at > scheduled_at)
);

alter table public.makeup_sessions enable row level security;
create policy "staff_manage_makeup_sessions" on public.makeup_sessions for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy "family_read_makeup_sessions" on public.makeup_sessions for select to authenticated using (
  exists (
    select 1 from public.attendance a
    join public.students s on s.id = a.student_id
    where a.id = attendance_id and s.profile_id = auth.uid()
  ) or exists (
    select 1 from public.attendance a
    join public.student_guardians sg on sg.student_id = a.student_id
    join public.guardians g on g.id = sg.guardian_id
    where a.id = attendance_id and g.profile_id = auth.uid()
  )
);
grant select, insert, update, delete on table public.makeup_sessions to authenticated;

create or replace function public.makeup_board()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'isStaff', public.is_staff(),
    'teachers', case when public.is_staff() then coalesce((select jsonb_agg(jsonb_build_object('id', p.id, 'name', p.display_name) order by p.display_name) from public.profiles p where p.role in ('admin', 'teacher')), '[]'::jsonb) else '[]'::jsonb end,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'attendanceId', a.id,
        'studentId', s.id,
        'studentName', s.name,
        'className', c.name,
        'missedDate', l.lesson_date,
        'attendanceNote', a.note,
        'sessionId', ms.id,
        'teacherId', ms.teacher_profile_id,
        'teacherName', tp.display_name,
        'scheduledAt', ms.scheduled_at,
        'endsAt', ms.ends_at,
        'room', ms.room,
        'status', ms.status,
        'note', ms.note
      ) order by coalesce(ms.scheduled_at, l.starts_at), s.name)
      from public.attendance a
      join public.lessons l on l.id = a.lesson_id
      join public.classes c on c.id = l.class_id
      join public.students s on s.id = a.student_id
      left join public.makeup_sessions ms on ms.attendance_id = a.id
      left join public.profiles tp on tp.id = ms.teacher_profile_id
      where (
        public.is_staff() and (a.makeup_required or ms.id is not null)
      ) or (
        not public.is_staff() and ms.id is not null and ms.status <> 'cancelled' and (
          s.profile_id = auth.uid() or exists (
            select 1 from public.student_guardians sg join public.guardians g on g.id = sg.guardian_id
            where sg.student_id = s.id and g.profile_id = auth.uid()
          )
        )
      )
    ), '[]'::jsonb)
  )
$$;

create or replace function public.staff_save_makeup(
  p_attendance_id uuid,
  p_teacher_id uuid,
  p_date date,
  p_start_time time,
  p_end_time time,
  p_room text,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  missed_record record;
  start_at timestamptz;
  end_at timestamptz;
  saved_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 보강을 예약할 수 있습니다.'; end if;
  if p_start_time >= p_end_time then raise exception '종료 시간은 시작 시간보다 늦어야 합니다.'; end if;
  if nullif(trim(p_room), '') is null then raise exception '강의실을 입력해 주세요.'; end if;
  if not exists (select 1 from public.profiles p where p.id = p_teacher_id and p.role in ('admin', 'teacher')) then raise exception '로그인한 교직원 계정만 담당할 수 있습니다.'; end if;
  select a.id, a.student_id, l.class_id into missed_record
  from public.attendance a join public.lessons l on l.id = a.lesson_id
  where a.id = p_attendance_id and a.makeup_required;
  if missed_record.id is null then raise exception '보강이 필요한 결석 기록을 찾을 수 없습니다.'; end if;

  start_at := ((p_date + p_start_time) at time zone 'Asia/Seoul');
  end_at := ((p_date + p_end_time) at time zone 'Asia/Seoul');

  if exists (
    select 1 from public.class_schedules cs
    join public.class_teachers ct on ct.class_id = cs.class_id and ct.profile_id = p_teacher_id
    where cs.weekday = extract(isodow from p_date)::smallint
      and cs.start_time < p_end_time and cs.end_time > p_start_time
      and (cs.valid_from is null or cs.valid_from <= p_date) and (cs.valid_until is null or cs.valid_until >= p_date)
      and not exists (select 1 from public.schedule_exceptions se where se.class_id = cs.class_id and se.original_date = p_date and se.kind = 'cancelled')
  ) then raise exception '담당 선생님에게 겹치는 정규 수업이 있습니다.'; end if;

  if exists (
    select 1 from public.class_schedules cs join public.classes c on c.id = cs.class_id
    where cs.weekday = extract(isodow from p_date)::smallint and c.room = trim(p_room)
      and cs.start_time < p_end_time and cs.end_time > p_start_time
      and (cs.valid_from is null or cs.valid_from <= p_date) and (cs.valid_until is null or cs.valid_until >= p_date)
      and not exists (select 1 from public.schedule_exceptions se where se.class_id = cs.class_id and se.original_date = p_date and se.kind = 'cancelled')
  ) then raise exception '선택한 강의실에 겹치는 정규 수업이 있습니다.'; end if;

  if exists (
    select 1 from public.makeup_sessions ms
    where ms.attendance_id <> p_attendance_id and ms.status = 'scheduled'
      and ms.scheduled_at < end_at and ms.ends_at > start_at
      and (ms.teacher_profile_id = p_teacher_id or ms.room = trim(p_room))
  ) then raise exception '담당 선생님 또는 강의실에 겹치는 보강이 있습니다.'; end if;

  insert into public.makeup_sessions(attendance_id, teacher_profile_id, scheduled_at, ends_at, room, status, note)
  values (p_attendance_id, p_teacher_id, start_at, end_at, trim(p_room), 'scheduled', nullif(trim(p_note), ''))
  on conflict (attendance_id) do update set teacher_profile_id = excluded.teacher_profile_id, scheduled_at = excluded.scheduled_at, ends_at = excluded.ends_at, room = excluded.room, status = 'scheduled', note = excluded.note
  returning id into saved_id;
  update public.attendance set makeup_required = true where id = p_attendance_id;
  return saved_id;
end
$$;

create or replace function public.staff_set_makeup_status(p_session_id uuid, p_status public.makeup_status)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare target_attendance_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 보강 상태를 변경할 수 있습니다.'; end if;
  update public.makeup_sessions set status = p_status where id = p_session_id returning attendance_id into target_attendance_id;
  if target_attendance_id is null then raise exception '보강 일정을 찾을 수 없습니다.'; end if;
  update public.attendance set makeup_required = (p_status <> 'completed') where id = target_attendance_id;
end
$$;

revoke all on function public.makeup_board() from public;
revoke all on function public.staff_save_makeup(uuid, uuid, date, time, time, text, text) from public;
revoke all on function public.staff_set_makeup_status(uuid, public.makeup_status) from public;
grant execute on function public.makeup_board() to authenticated;
grant execute on function public.staff_save_makeup(uuid, uuid, date, time, time, text, text) to authenticated;
grant execute on function public.staff_set_makeup_status(uuid, public.makeup_status) to authenticated;
