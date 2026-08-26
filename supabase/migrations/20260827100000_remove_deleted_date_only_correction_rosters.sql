create or replace function public.staff_delete_correction_reports(p_records jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  item jsonb;
  v_assignment_id uuid;
  v_correction_date date;
  v_start_time time;
  v_deleted_count integer;
begin
  if not public.is_staff() then
    raise exception '교직원만 첨삭 기록을 삭제할 수 있습니다.';
  end if;

  for item in select value from jsonb_array_elements(coalesce(p_records, '[]'::jsonb))
  loop
    v_assignment_id := nullif(item->>'assignmentId','')::uuid;
    v_correction_date := nullif(item->>'date','')::date;
    v_start_time := nullif(item->>'startTime','')::time;

    if v_assignment_id is null or v_correction_date is null or v_start_time is null then
      raise exception '삭제할 첨삭 기록을 확인해 주세요.';
    end if;

    delete from public.correction_reports as report
    where report.assignment_id = v_assignment_id
      and report.correction_date = v_correction_date
      and report.start_time = v_start_time;

    get diagnostics v_deleted_count = row_count;

    if v_deleted_count > 0 then
      delete from public.correction_assignments as assignment
      where assignment.id = v_assignment_id
        and not assignment.active
        and assignment.valid_from <= v_correction_date
        and assignment.valid_until >= v_correction_date
        and (timezone('Asia/Seoul', assignment.created_at))::date > assignment.valid_until;
    end if;
  end loop;
end;
$$;

revoke all on function public.staff_delete_correction_reports(jsonb) from public, anon;
grant execute on function public.staff_delete_correction_reports(jsonb) to authenticated;

notify pgrst, 'reload schema';
