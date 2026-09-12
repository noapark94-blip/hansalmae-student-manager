-- Share schedule reads; existing owner/admin write checks remain in force.
CREATE OR REPLACE FUNCTION public.staff_teacher_special_lessons(p_teacher_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role public.user_role; v_teacher uuid;
begin
  if auth.uid() is null or not public.is_staff() then raise exception '교직원만 확인할 수 있습니다.'; end if;
  v_role:=public.current_user_role();
  v_teacher:=case when v_role in ('admin','teacher','sub_admin') then p_teacher_id else auth.uid() end;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'reminderRecipientIds',coalesce(l.reminder_recipient_ids,array_remove(array[l.teacher_profile_id],null)),'reminderEnabled',l.reminder_enabled,'id',l.id,'date',l.lesson_date,'startTime',l.starts_at,'endTime',l.ends_at,'kind',l.kind,
    'subjectId',l.subject_id,'subject',s.name,'mainSubject',s.main_subject,
    'room',l.room,'note',l.note,'teacherName',p.display_name,'teacherId',l.teacher_profile_id,
    'students',coalesce((select jsonb_agg(jsonb_build_object(
      'id',st.id,'name',st.name,'school',st.school,'grade',st.grade,
      'attendanceStatus',a.attendance_status
    ) order by st.name)
      from public.teacher_special_lesson_students a
      join public.students st on st.id=a.student_id
      where a.session_id=l.id),'[]'::jsonb)
  ) order by l.lesson_date,l.starts_at)
  from public.teacher_special_lessons l
  join public.profiles p on p.id=l.teacher_profile_id
  left join public.academy_subjects s on s.id=l.subject_id
  where v_teacher is null or l.teacher_profile_id=v_teacher),'[]'::jsonb);
end $function$;

revoke all on function public.staff_teacher_special_lessons(uuid) from public, anon;
grant execute on function public.staff_teacher_special_lessons(uuid) to authenticated;
notify pgrst, 'reload schema';
