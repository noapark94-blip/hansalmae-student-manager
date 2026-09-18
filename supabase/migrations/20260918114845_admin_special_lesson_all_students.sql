create or replace function public.staff_special_lesson_student_options(p_teacher_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not coalesce(public.is_staff(),false) then raise exception '교직원만 확인할 수 있습니다.'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade) order by s.name,s.id)
 from public.students s where s.status='active' and (
 public.current_user_role()='admin' or exists(
 select 1 from public.enrollments e join public.classes c on c.id=e.class_id and c.active
 join public.class_teachers ct on ct.class_id=c.id and ct.profile_id=auth.uid()
 where e.student_id=s.id and e.status='active'
 ))),'[]'::jsonb);
end $$;
revoke all on function public.staff_special_lesson_student_options(uuid) from public,anon;
grant execute on function public.staff_special_lesson_student_options(uuid) to authenticated;
