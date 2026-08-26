-- 과거 누락 학생 보정 배정을 기록 화면에서 구분하고 정규 시간표에서는 제외할 수 있게 표시합니다.

create or replace function public.correction_day_board(p_date text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_date date:=coalesce(nullif(p_date,'')::date,(timezone('Asia/Seoul',now()))::date);v_weekday int:=extract(isodow from v_date)::int;
begin
  if not public.is_staff() then raise exception '교직원만 첨삭 진행 명단을 확인할 수 있습니다.'; end if;
  return jsonb_build_object(
    'assignments',coalesce((select jsonb_agg(jsonb_build_object(
      'id',a.id,'studentId',a.student_id,'studentName',s.name,'school',s.school,'grade',s.grade,'subject',a.subject,
      'weekday',a.weekday,'startTime',to_char(a.start_time,'HH24:MI:SS'),'endTime',to_char(a.end_time,'HH24:MI:SS'),
      'validFrom',to_char(a.valid_from,'YYYY-MM-DD'),'validUntil',case when a.valid_until is null then null else to_char(a.valid_until,'YYYY-MM-DD') end,
      'isDateOverride',(not a.active and a.valid_until is not null and (timezone('Asia/Seoul',a.created_at))::date>a.valid_until),
      'tutorName',tp.display_name,'supervisorName',sp.display_name,'note',a.note
    ) order by a.start_time,a.subject,s.name)
      from public.correction_assignments a join public.students s on s.id=a.student_id
      left join public.profiles tp on tp.id=a.tutor_profile_id left join public.profiles sp on sp.id=a.supervisor_profile_id
      where a.subject is not null and (
        (a.weekday=v_weekday and a.valid_from<=v_date and (a.valid_until is null or a.valid_until>=v_date))
        or exists(select 1 from public.correction_schedule_exceptions x where x.assignment_id=a.id and (x.original_date=v_date or x.target_date=v_date))
      )),'[]'::jsonb),
    'exceptions',coalesce((select jsonb_agg(jsonb_build_object(
      'id',e.id,'assignmentId',e.assignment_id,'originalDate',to_char(e.original_date,'YYYY-MM-DD'),'kind',e.kind,
      'targetDate',case when e.target_date is null then null else to_char(e.target_date,'YYYY-MM-DD') end,
      'targetStartTime',case when e.target_start_time is null then null else to_char(e.target_start_time,'HH24:MI:SS') end,
      'targetEndTime',case when e.target_end_time is null then null else to_char(e.target_end_time,'HH24:MI:SS') end,'note',e.note
    ) order by e.created_at)
      from public.correction_schedule_exceptions e join public.correction_assignments a on a.id=e.assignment_id
      where a.subject is not null and (e.original_date=v_date or e.target_date=v_date)),'[]'::jsonb)
  );
end $$;

create or replace function public.correction_management_board_v2(p_anchor text default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_anchor date:=coalesce(nullif(p_anchor,'')::date,(timezone('Asia/Seoul',now()))::date);v_start date;v_end date;
begin
  if not public.is_staff() then raise exception '교직원만 첨삭 관리를 확인할 수 있습니다.'; end if;
  v_start:=v_anchor-(extract(isodow from v_anchor)::int-1);v_end:=v_start+6;
  return jsonb_build_object(
    'weekStart',to_char(v_start,'YYYY-MM-DD'),
    'students',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade) order by s.name) from public.students s where s.status in ('active','재원')),'[]'::jsonb),
    'staff',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name) from public.profiles p where p.role::text in ('admin','teacher')),'[]'::jsonb),
    'assignments',coalesce((select jsonb_agg(jsonb_build_object(
      'id',a.id,'studentId',a.student_id,'studentName',s.name,'school',s.school,'grade',s.grade,'subject',a.subject,
      'weekday',a.weekday,'startTime',to_char(a.start_time,'HH24:MI:SS'),'endTime',to_char(a.end_time,'HH24:MI:SS'),
      'validFrom',to_char(a.valid_from,'YYYY-MM-DD'),'validUntil',case when a.valid_until is null then null else to_char(a.valid_until,'YYYY-MM-DD') end,
      'isDateOverride',(not a.active and a.valid_until is not null and (timezone('Asia/Seoul',a.created_at))::date>a.valid_until),
      'tutorId',a.tutor_profile_id,'tutorName',tp.display_name,'supervisorId',a.supervisor_profile_id,'supervisorName',sp.display_name,'note',a.note
    ) order by a.weekday,a.start_time,a.subject,s.name)
      from public.correction_assignments a join public.students s on s.id=a.student_id
      left join public.profiles tp on tp.id=a.tutor_profile_id left join public.profiles sp on sp.id=a.supervisor_profile_id
      where a.subject is not null and a.start_time is not null and a.end_time is not null
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
      where a.subject is not null and (e.original_date between v_start and v_end or (e.target_date is not null and e.target_date between v_start and v_end))),'[]'::jsonb)
  );
end $$;

revoke all on function public.correction_day_board(text),public.correction_management_board_v2(text) from public,anon;
grant execute on function public.correction_day_board(text),public.correction_management_board_v2(text) to authenticated;

notify pgrst,'reload schema';
