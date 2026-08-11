-- 정규 시간표에서 날짜별 수업을 준비하고 출결 변경과 보강 상태를 자동으로 맞춥니다.

create table public.attendance_status_history (
  id uuid primary key default gen_random_uuid(),
  attendance_id uuid not null references public.attendance(id) on delete cascade,
  previous_status public.attendance_status,
  next_status public.attendance_status not null,
  changed_by uuid references public.profiles(id) on delete set null,
  changed_at timestamptz not null default now()
);

create index attendance_status_history_attendance_idx on public.attendance_status_history(attendance_id, changed_at desc);
alter table public.attendance_status_history enable row level security;
create policy "staff_read_attendance_status_history" on public.attendance_status_history for select to authenticated using (public.is_staff());
grant select on table public.attendance_status_history to authenticated;

create or replace function public.staff_prepare_daily_attendance(p_date date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare created_count integer := 0; lesson_count integer := 0; roster_count integer := 0;
begin
  if not public.is_staff() then raise exception '교직원만 출석부를 준비할 수 있습니다.'; end if;
  with scheduled as (
    select c.id class_id, c.room, cs.start_time, cs.end_time
    from public.class_schedules cs join public.classes c on c.id=cs.class_id
    where c.active and cs.weekday=extract(isodow from p_date)::smallint
      and (cs.valid_from is null or cs.valid_from<=p_date) and (cs.valid_until is null or cs.valid_until>=p_date)
      and not exists(select 1 from public.schedule_exceptions se where se.class_id=c.id and se.original_date=p_date and se.kind='cancelled')
  ), inserted as (
    insert into public.lessons(class_id,lesson_date,starts_at,ends_at,room)
    select class_id,p_date,((p_date+start_time) at time zone 'Asia/Seoul'),((p_date+end_time) at time zone 'Asia/Seoul'),room from scheduled
    on conflict (class_id,starts_at) do nothing returning id
  ) select count(*) into created_count from inserted;
  select count(*) into lesson_count from public.lessons l where l.lesson_date=p_date and l.status='scheduled';
  select count(*) into roster_count from public.lessons l join public.enrollments e on e.class_id=l.class_id join public.students s on s.id=e.student_id
  where l.lesson_date=p_date and l.status='scheduled' and e.status='active' and e.started_on<=p_date and (e.ended_on is null or e.ended_on>=p_date) and s.status in ('active','재원');
  return jsonb_build_object('createdLessons',created_count,'lessonCount',lesson_count,'studentCount',roster_count);
end $$;

create or replace function public.sync_attendance_makeup_state()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.status='absent' then
    new.makeup_required := not exists(select 1 from public.makeup_sessions ms where ms.attendance_id=new.id and ms.status='completed');
  else new.makeup_required := false;
  end if;
  return new;
end $$;
create trigger attendance_sync_makeup_state before insert or update of status on public.attendance for each row execute function public.sync_attendance_makeup_state();

create or replace function public.record_attendance_status_change()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' or old.status is distinct from new.status then
    insert into public.attendance_status_history(attendance_id,previous_status,next_status,changed_by)
    values(new.id,case when tg_op='UPDATE' then old.status else null end,new.status,auth.uid());
  end if;
  if new.status<>'absent' and (tg_op='INSERT' or old.status is distinct from new.status) then
    update public.makeup_sessions set status='cancelled',note=concat_ws(' · ',nullif(note,''),'출결 수정으로 자동 취소')
    where attendance_id=new.id and status='scheduled';
  end if;
  return new;
end $$;
create trigger attendance_record_status_change after insert or update of status on public.attendance for each row execute function public.record_attendance_status_change();

revoke all on function public.staff_prepare_daily_attendance(date) from public;
grant execute on function public.staff_prepare_daily_attendance(date) to authenticated;
