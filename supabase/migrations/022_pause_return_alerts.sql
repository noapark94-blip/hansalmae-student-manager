-- 휴원 학생의 복귀 예정일을 기록하고 홈 알림으로 제공합니다.

alter table public.students add column pause_return_expected_on date;
alter table public.student_status_history add column return_expected_on date;

drop function public.staff_set_student_lifecycle(uuid,text,date,text);

create function public.staff_set_student_lifecycle(p_student_id uuid,p_status text,p_effective_on date,p_note text default null,p_return_expected_on date default null)
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
  if p_status='paused' and (p_return_expected_on is null or p_return_expected_on<p_effective_on) then raise exception '복귀 예정일은 휴원 적용일 이후로 선택해 주세요.'; end if;
  select status into previous from public.students where id=p_student_id for update;
  if previous is null then raise exception '학생을 찾을 수 없습니다.'; end if;
  if previous=p_status then raise exception '이미 같은 재원 상태입니다.'; end if;
  if p_status in ('paused','completed') and exists(select 1 from public.enrollments e where e.student_id=p_student_id and e.status='active' and e.started_on>p_effective_on) then raise exception '적용일이 현재 수강 시작일보다 빠릅니다.'; end if;

  if p_status in ('paused','completed') then
    update public.enrollments set status=case when p_status='paused' then 'paused'::public.enrollment_status else 'completed'::public.enrollment_status end,ended_on=p_effective_on where student_id=p_student_id and status='active';
  end if;
  update public.students set status=p_status,pause_return_expected_on=case when p_status='paused' then p_return_expected_on else null end where id=p_student_id;
  insert into public.student_status_history(student_id,previous_status,new_status,effective_on,note,changed_by,return_expected_on) values(p_student_id,previous,p_status,p_effective_on,nullif(trim(p_note),''),auth.uid(),case when p_status='paused' then p_return_expected_on else null end);
end
$$;

create or replace function public.staff_student_lifecycle_history(p_student_id uuid)
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select case when public.is_staff() then coalesce((select jsonb_agg(jsonb_build_object('id',h.id,'previousStatus',case h.previous_status when '재원' then 'active' when '휴원' then 'paused' when '퇴원' then 'completed' else h.previous_status end,'newStatus',h.new_status,'effectiveOn',h.effective_on,'returnExpectedOn',h.return_expected_on,'note',h.note,'changedByName',p.display_name,'createdAt',h.created_at) order by h.effective_on desc,h.created_at desc) from public.student_status_history h join public.profiles p on p.id=h.changed_by where h.student_id=p_student_id),'[]'::jsonb) else null end
$$;

create or replace function public.staff_pause_return_alerts(p_days integer default 7)
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select case when public.is_staff() then jsonb_build_object(
    'overdue',count(*) filter(where s.pause_return_expected_on<current_date),
    'upcoming',count(*) filter(where s.pause_return_expected_on between current_date and current_date+p_days),
    'students',coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'expectedOn',s.pause_return_expected_on,'overdue',s.pause_return_expected_on<current_date) order by s.pause_return_expected_on) filter(where s.pause_return_expected_on<=current_date+p_days),'[]'::jsonb)
  ) else null end
  from public.students s
  where s.status in ('paused','휴원') and s.pause_return_expected_on is not null
$$;

revoke all on function public.staff_set_student_lifecycle(uuid,text,date,text,date) from public;
revoke all on function public.staff_pause_return_alerts(integer) from public;
grant execute on function public.staff_set_student_lifecycle(uuid,text,date,text,date) to authenticated;
grant execute on function public.staff_pause_return_alerts(integer) to authenticated;
