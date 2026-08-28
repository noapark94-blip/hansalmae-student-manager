-- 학생·학부모 정규시간표에 정규 첨삭 고정 배정을 안전하게 제공합니다.

create or replace function public.family_regular_correction_timetable(p_student_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare base jsonb; selected_id uuid; today date := (timezone('Asia/Seoul',now()))::date;
begin
  base:=public.family_live_dashboard(p_student_id);
  selected_id:=nullif(base->'selectedStudent'->>'id','')::uuid;
  if selected_id is null then return '[]'::jsonb; end if;

  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',a.id,'subject',a.subject,'weekday',a.weekday,
    'startTime',to_char(a.start_time,'HH24:MI:SS'),'endTime',to_char(a.end_time,'HH24:MI:SS'),
    'teacherName',coalesce(tp.display_name,lp.display_name,'담당 선생님')
  ) order by a.weekday,a.start_time,a.subject)
  from public.correction_assignments a
  left join public.profiles tp on tp.id=a.tutor_profile_id
  left join public.profiles lp on lp.id=a.teacher_profile_id
  where a.student_id=selected_id and a.active and a.subject is not null
    and a.start_time is not null and a.end_time is not null
    and a.valid_from<=today and (a.valid_until is null or a.valid_until>=today)),'[]'::jsonb);
end $$;

revoke all on function public.family_regular_correction_timetable(uuid) from public,anon;
grant execute on function public.family_regular_correction_timetable(uuid) to authenticated;
notify pgrst,'reload schema';
