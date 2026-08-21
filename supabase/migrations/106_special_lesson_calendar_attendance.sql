create or replace function public.staff_teacher_special_lessons(p_teacher_id uuid default null)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_role public.user_role; v_teacher uuid;
begin
  if not public.is_staff() then raise exception '교직원만 확인할 수 있습니다.'; end if;
  v_role:=public.current_user_role();
  v_teacher:=case when v_role='admin' then p_teacher_id else auth.uid() end;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',l.id,'date',l.lesson_date,'startTime',l.starts_at,'endTime',l.ends_at,'kind',l.kind,
    'room',l.room,'note',l.note,'teacherName',p.display_name,'teacherId',l.teacher_profile_id,
    'students',coalesce((select jsonb_agg(jsonb_build_object(
      'id',s.id,'name',s.name,'school',s.school,'grade',s.grade,
      'attendanceStatus',a.attendance_status
    ) order by s.name)
      from public.teacher_special_lesson_students a
      join public.students s on s.id=a.student_id
      where a.session_id=l.id),'[]'::jsonb)
  ) order by l.lesson_date,l.starts_at)
  from public.teacher_special_lessons l
  join public.profiles p on p.id=l.teacher_profile_id
  where v_teacher is null or l.teacher_profile_id=v_teacher),'[]'::jsonb);
end $$;

revoke all on function public.staff_teacher_special_lessons(uuid) from public;
grant execute on function public.staff_teacher_special_lessons(uuid) to authenticated;
notify pgrst,'reload schema';
