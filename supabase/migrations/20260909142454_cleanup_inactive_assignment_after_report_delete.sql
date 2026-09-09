-- 학생별 첨삭 기록 삭제 후 이미 종료된 고정 배정이 오늘 명단에 남지 않도록 정리합니다.
create or replace function public.staff_delete_correction_reports(p_records jsonb)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  item jsonb;
  v_assignment_id uuid;
  v_correction_date date;
  v_start_time time;
  v_assignment public.correction_assignments;
  v_last_record date;
  v_today date:=(timezone('Asia/Seoul',now()))::date;
begin
  if not public.is_staff() then
    raise exception '교직원만 첨삭 기록을 삭제할 수 있습니다.';
  end if;

  for item in select value from jsonb_array_elements(coalesce(p_records,'[]'::jsonb))
  loop
    v_assignment_id:=nullif(item->>'assignmentId','')::uuid;
    v_correction_date:=nullif(item->>'date','')::date;
    v_start_time:=nullif(item->>'startTime','')::time;

    if v_assignment_id is null or v_correction_date is null or v_start_time is null then
      raise exception '삭제할 첨삭 기록을 확인해 주세요.';
    end if;

    select * into v_assignment
    from public.correction_assignments
    where id=v_assignment_id and subject is not null
    for update;

    if v_assignment.id is null then
      raise exception '첨삭 배정을 찾을 수 없습니다.';
    end if;

    delete from public.correction_reports
    where assignment_id=v_assignment_id
      and correction_date=v_correction_date
      and start_time=v_start_time;

    if not v_assignment.active then
      select max(correction_date) into v_last_record
      from public.correction_reports
      where assignment_id=v_assignment_id;

      if v_last_record is null then
        delete from public.correction_assignments where id=v_assignment_id;
      else
        update public.correction_assignments
        set valid_until=greatest(valid_from,v_last_record,v_today-1),updated_at=now()
        where id=v_assignment_id;
      end if;
    end if;
  end loop;
end;
$$;

revoke all on function public.staff_delete_correction_reports(jsonb) from public,anon;
grant execute on function public.staff_delete_correction_reports(jsonb) to authenticated;

notify pgrst,'reload schema';
