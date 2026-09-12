-- Notifications contain identifiers only; actual content uses the staff-authorized RPC.
create table public.correction_timetable_signals (
  key text primary key,
  assignment_id uuid,
  changed_at timestamptz not null default clock_timestamp()
);
alter table public.correction_timetable_signals enable row level security;
revoke all on public.correction_timetable_signals from public, anon, authenticated;
grant select on public.correction_timetable_signals to authenticated;
create policy correction_timetable_signals_staff_read on public.correction_timetable_signals
for select to authenticated using ((select auth.uid()) is not null and (select public.is_staff()));

create function public.notify_correction_timetable_change() returns trigger
language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_old_id uuid;
begin
  if tg_table_name='correction_slot_assistants' then
    insert into public.correction_timetable_signals(key) values ('assistants')
    on conflict(key) do update set changed_at=clock_timestamp();
    return null;
  end if;
  if tg_table_name='correction_assignments' then
    if tg_op='DELETE' then v_id:=old.id; else v_id:=new.id; end if;
  else
    if tg_op='DELETE' then v_id:=old.assignment_id; else v_id:=new.assignment_id; end if;
    if tg_op='UPDATE' then v_old_id:=old.assignment_id; end if;
  end if;
  insert into public.correction_timetable_signals(key,assignment_id) values(v_id::text,v_id)
  on conflict(key) do update set changed_at=clock_timestamp();
  if v_old_id is not null and v_old_id<>v_id then
    insert into public.correction_timetable_signals(key,assignment_id) values(v_old_id::text,v_old_id)
    on conflict(key) do update set changed_at=clock_timestamp();
  end if;
  return null;
end $$;
revoke all on function public.notify_correction_timetable_change() from public,anon,authenticated;
create trigger correction_assignments_live_change after insert or update or delete on public.correction_assignments
for each row execute function public.notify_correction_timetable_change();
create trigger correction_exceptions_live_change after insert or update or delete on public.correction_schedule_exceptions
for each row execute function public.notify_correction_timetable_change();
create trigger correction_assistants_live_change after insert or update or delete on public.correction_slot_assistants
for each row execute function public.notify_correction_timetable_change();
alter publication supabase_realtime add table public.correction_timetable_signals;

CREATE OR REPLACE FUNCTION public.correction_timetable_updates(p_anchor text, p_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_anchor date:=coalesce(nullif(p_anchor,'')::date,(timezone('Asia/Seoul',now()))::date);v_start date;v_end date;
begin
  if auth.uid() is null or not coalesce(public.is_staff(),false) then raise exception '교직원만 첨삭 관리를 확인할 수 있습니다.'; end if;
  v_start:=v_anchor-(extract(isodow from v_anchor)::int-1);v_end:=v_start+6;
  return jsonb_build_object(
    'weekStart',to_char(v_start,'YYYY-MM-DD'),
    'assignments',coalesce((select jsonb_agg(jsonb_build_object(
      'id',a.id,'studentId',a.student_id,'studentName',s.name,'school',s.school,'grade',s.grade,'subject',a.subject,
      'weekday',a.weekday,'startTime',to_char(a.start_time,'HH24:MI:SS'),'endTime',to_char(a.end_time,'HH24:MI:SS'),
      'active',a.active,'validFrom',to_char(a.valid_from,'YYYY-MM-DD'),'validUntil',case when a.valid_until is null then null else to_char(a.valid_until,'YYYY-MM-DD') end,
      'isDateOverride',(not a.active and a.valid_until is not null and (timezone('Asia/Seoul',a.created_at))::date>a.valid_until),
      'tutorId',a.tutor_profile_id,'tutorName',tp.display_name,'supervisorId',a.supervisor_profile_id,'supervisorName',sp.display_name,'note',a.note
    ) order by a.weekday,a.start_time,a.subject,s.name)
      from public.correction_assignments a join public.students s on s.id=a.student_id
      left join public.profiles tp on tp.id=a.tutor_profile_id left join public.profiles sp on sp.id=a.supervisor_profile_id
      where a.id = any(p_ids) and a.subject is not null and a.start_time is not null and a.end_time is not null
        and (
          (a.valid_from<=v_end and (a.valid_until is null or a.valid_until>=v_start))
          or exists(select 1 from public.correction_schedule_exceptions x where x.assignment_id=a.id and (x.original_date between v_start and v_end or x.target_date between v_start and v_end))
        )),'[]'::jsonb),
    'exceptions',coalesce((select jsonb_agg(jsonb_build_object(
      'id',e.id,'assignmentId',e.assignment_id,'originalDate',to_char(e.original_date,'YYYY-MM-DD'),'kind',e.kind,
      'targetDate',case when e.target_date is null then null else to_char(e.target_date,'YYYY-MM-DD') end,
      'targetStartTime',case when e.target_start_time is null then null else to_char(e.target_start_time,'HH24:MI:SS') end,
      'targetEndTime',case when e.target_end_time is null then null else to_char(e.target_end_time,'HH24:MI:SS') end,'note',e.note
    ) order by e.original_date,e.created_at)
      from public.correction_schedule_exceptions e join public.correction_assignments a on a.id=e.assignment_id
      where a.id = any(p_ids) and a.subject is not null and (e.original_date between v_start and v_end or (e.target_date is not null and e.target_date between v_start and v_end))),'[]'::jsonb)
  );
end $function$;

revoke all on function public.correction_timetable_updates(text,uuid[]) from public,anon;
grant execute on function public.correction_timetable_updates(text,uuid[]) to authenticated;
