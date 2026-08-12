-- 관리자가 수업도 담당할 때, 관리자 권한은 유지하면서 배정된 클래스만 개인 홈에 표시합니다.

create or replace function public.teacher_class_workspace()
returns jsonb language sql stable security definer set search_path=public as $$
  select case when public.is_staff() then jsonb_build_object(
    'subjects',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'mainSubject',s.main_subject,'parentId',s.parent_id) order by case s.main_subject when '국어' then 1 when '영어' then 2 else 3 end,s.parent_id nulls first,s.name) from public.academy_subjects s where s.active),'[]'::jsonb),
    'classes',coalesce((select jsonb_agg(jsonb_build_object(
      'id',c.id,'name',c.name,'subject',c.subject,'subjectId',c.subject_id,'room',c.room,'color',c.color,
      'schedules',coalesce((select jsonb_agg(jsonb_build_object('id',cs.id,'weekday',cs.weekday,'startTime',cs.start_time,'endTime',cs.end_time) order by cs.weekday,cs.start_time) from public.class_schedules cs where cs.class_id=c.id and (cs.valid_until is null or cs.valid_until>=current_date)),'[]'::jsonb),
      'students',coalesce((select jsonb_agg(jsonb_build_object('id',st.id,'name',st.name,'school',st.school,'grade',st.grade) order by st.name) from public.enrollments e join public.students st on st.id=e.student_id where e.class_id=c.id and e.status='active'),'[]'::jsonb)
    ) order by c.subject,c.name) from public.classes c where c.active and exists(select 1 from public.class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid())),'[]'::jsonb)
  ) else null end
$$;

revoke all on function public.teacher_class_workspace() from public;
grant execute on function public.teacher_class_workspace() to authenticated;
