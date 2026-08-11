-- 교직원이 학생 현황과 최근 재원 변동을 한 번에 조회합니다.

create or replace function public.staff_student_lifecycle_dashboard(p_days integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare result jsonb;
begin
  if not coalesce(public.is_staff(),false) then raise exception '교직원만 재원 변동 현황을 확인할 수 있습니다.'; end if;
  if p_days not between 7 and 365 then raise exception '조회 기간은 7일에서 365일 사이여야 합니다.'; end if;

  select jsonb_build_object(
    'current',jsonb_build_object(
      'all',count(*),
      'active',count(*) filter(where s.status in ('active','재원')),
      'paused',count(*) filter(where s.status in ('paused','휴원')),
      'completed',count(*) filter(where s.status in ('completed','퇴원'))
    ),
    'period',jsonb_build_object(
      'active',(select count(*) from public.student_status_history h where h.new_status='active' and h.effective_on>=current_date-p_days+1),
      'paused',(select count(*) from public.student_status_history h where h.new_status='paused' and h.effective_on>=current_date-p_days+1),
      'completed',(select count(*) from public.student_status_history h where h.new_status='completed' and h.effective_on>=current_date-p_days+1)
    ),
    'recent',coalesce((select jsonb_agg(row_data order by effective_on desc,created_at desc) from (
      select jsonb_build_object('id',h.id,'studentId',h.student_id,'studentName',s2.name,'previousStatus',h.previous_status,'newStatus',h.new_status,'effectiveOn',h.effective_on,'note',h.note,'changedByName',p.display_name) row_data,h.effective_on,h.created_at
      from public.student_status_history h
      join public.students s2 on s2.id=h.student_id
      join public.profiles p on p.id=h.changed_by
      where h.effective_on>=current_date-p_days+1
      order by h.effective_on desc,h.created_at desc
      limit 12
    ) recent_rows),'[]'::jsonb)
  ) into result
  from public.students s;
  return result;
end
$$;

revoke all on function public.staff_student_lifecycle_dashboard(integer) from public;
grant execute on function public.staff_student_lifecycle_dashboard(integer) to authenticated;
