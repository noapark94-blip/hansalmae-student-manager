-- 차량 운행표에서 요일별 공용 메모를 저장합니다.
create table if not exists public.vehicle_schedule_notes (
  weekday smallint primary key check (weekday between 1 and 5),
  note text not null default '',
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

create index if not exists vehicle_schedule_notes_updated_by_idx on public.vehicle_schedule_notes(updated_by);

alter table public.vehicle_schedule_notes enable row level security;

drop policy if exists vehicle_schedule_notes_staff on public.vehicle_schedule_notes;
create policy vehicle_schedule_notes_staff
on public.vehicle_schedule_notes
for all
to authenticated
using (public.is_staff())
with check (public.is_staff());

grant select,insert,update,delete on public.vehicle_schedule_notes to authenticated;
