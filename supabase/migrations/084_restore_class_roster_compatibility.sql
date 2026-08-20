create or replace function public.staff_students_with_enrollments()
returns jsonb language sql stable security definer set search_path=public as $$
  select case when public.is_staff() then coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,
    'name',s.name,
    'school',s.school,
    'grade',s.grade,
    'status',s.status,
    'enrollments',coalesce((select jsonb_agg(jsonb_build_object(
      'class_id',e.class_id,
      'status',e.status,
      'classes',jsonb_build_object('name',c.name,'subject',coalesce(sub.name,c.subject))
    )) from public.enrollments e join public.classes c on c.id=e.class_id left join public.academy_subjects sub on sub.id=c.subject_id where e.student_id=s.id),'[]'::jsonb)
  ) order by s.name),'[]'::jsonb) else '[]'::jsonb end
  from public.students s;
$$;

create or replace function public.staff_set_class_enrollment(p_class_id uuid,p_student_id uuid,p_active boolean)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception '교직원만 클래스 학생을 변경할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스의 학생만 변경할 수 있습니다.'; end if;
  if p_active then
    update public.enrollments set status='active',ended_on=null where student_id=p_student_id and class_id=p_class_id and status<>'active';
    if not found then insert into public.enrollments(student_id,class_id,status,started_on) values(p_student_id,p_class_id,'active',current_date); end if;
  else
    update public.enrollments set status='completed',ended_on=current_date where student_id=p_student_id and class_id=p_class_id and status='active';
  end if;
end $$;

revoke all on function public.staff_students_with_enrollments(),public.staff_set_class_enrollment(uuid,uuid,boolean) from public;
grant execute on function public.staff_students_with_enrollments(),public.staff_set_class_enrollment(uuid,uuid,boolean) to authenticated;
notify pgrst,'reload schema';
