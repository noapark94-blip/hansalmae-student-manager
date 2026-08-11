-- 학생을 삭제하지 않고 휴원·복귀·퇴원 이력과 수강 종료일을 보존합니다.

create table public.student_status_history (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  previous_status text not null,
  new_status text not null check (new_status in ('active','paused','completed')),
  effective_on date not null,
  note text,
  changed_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now(),
  check (previous_status in ('active','paused','completed','재원','휴원','퇴원'))
);

create index student_status_history_student_idx on public.student_status_history(student_id,effective_on desc,created_at desc);
alter table public.student_status_history enable row level security;
create policy "staff_read_student_status_history" on public.student_status_history for select to authenticated using (public.is_staff());
grant select on table public.student_status_history to authenticated;

create or replace function public.staff_set_student_lifecycle(p_student_id uuid,p_status text,p_effective_on date,p_note text default null)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare previous text;
begin
  if not coalesce(public.is_staff(),false) then raise exception '교직원만 재원 상태를 변경할 수 있습니다.'; end if;
  if p_status not in ('active','paused','completed') then raise exception '변경할 상태를 확인해 주세요.'; end if;
  if p_effective_on is null or p_effective_on>current_date then raise exception '적용일은 오늘 또는 이전 날짜만 선택할 수 있습니다.'; end if;
  if p_status<>'active' and nullif(trim(p_note),'') is null then raise exception '휴원·퇴원 사유를 입력해 주세요.'; end if;
  select status into previous from public.students where id=p_student_id for update;
  if previous is null then raise exception '학생을 찾을 수 없습니다.'; end if;
  if previous=p_status then raise exception '이미 같은 재원 상태입니다.'; end if;
  if p_status in ('paused','completed') and exists(select 1 from public.enrollments e where e.student_id=p_student_id and e.status='active' and e.started_on>p_effective_on) then raise exception '적용일이 현재 수강 시작일보다 빠릅니다.'; end if;

  if p_status in ('paused','completed') then
    update public.enrollments set status=case when p_status='paused' then 'paused'::public.enrollment_status else 'completed'::public.enrollment_status end,ended_on=p_effective_on where student_id=p_student_id and status='active';
  end if;
  update public.students set status=p_status where id=p_student_id;
  insert into public.student_status_history(student_id,previous_status,new_status,effective_on,note,changed_by) values(p_student_id,previous,p_status,p_effective_on,nullif(trim(p_note),''),auth.uid());
end
$$;

create or replace function public.staff_student_lifecycle_history(p_student_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select case when public.is_staff() then coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'previousStatus',case h.previous_status when '재원' then 'active' when '휴원' then 'paused' when '퇴원' then 'completed' else h.previous_status end,'newStatus',h.new_status,'effectiveOn',h.effective_on,'note',h.note,'changedByName',p.display_name,'createdAt',h.created_at) order by h.effective_on desc,h.created_at desc) from public.student_status_history h join public.profiles p on p.id=h.changed_by where h.student_id=p_student_id),'[]'::jsonb) else null end
$$;

revoke all on function public.staff_set_student_lifecycle(uuid,text,date,text) from public;
revoke all on function public.staff_student_lifecycle_history(uuid) from public;
grant execute on function public.staff_set_student_lifecycle(uuid,text,date,text) to authenticated;
grant execute on function public.staff_student_lifecycle_history(uuid) to authenticated;
