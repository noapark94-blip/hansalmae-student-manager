-- 한 학생의 여러 과목·반 수강 변경을 원자적으로 처리하고 이전 이력을 보존합니다.
create or replace function public.staff_sync_student_enrollments(
  p_student_id uuid,
  p_class_ids uuid[] default '{}'::uuid[]
)
returns void language plpgsql security definer set search_path=public as $$
declare requested_ids uuid[]:=coalesce(array(select distinct item from unnest(coalesce(p_class_ids,'{}'::uuid[])) as item),'{}'::uuid[]);
begin
  if not public.is_staff() then raise exception '교직원만 학생 수강 클래스를 변경할 수 있습니다.'; end if;
  if not exists(select 1 from public.students where id=p_student_id) then raise exception '학생을 찾을 수 없습니다.'; end if;
  if exists(select 1 from unnest(requested_ids) requested_id left join public.classes c on c.id=requested_id where c.id is null or not c.active) then raise exception '운영 중인 클래스만 수강에 배정할 수 있습니다.'; end if;

  update public.enrollments set status='completed',ended_on=current_date
  where student_id=p_student_id and status='active' and not (class_id=any(requested_ids));

  insert into public.enrollments(student_id,class_id,status,started_on)
  select p_student_id,requested_id,'active',current_date from unnest(requested_ids) requested_id
  where not exists(select 1 from public.enrollments e where e.student_id=p_student_id and e.class_id=requested_id and e.status='active')
  on conflict(student_id,class_id,started_on) do update set status='active',ended_on=null;
end $$;

revoke all on function public.staff_sync_student_enrollments(uuid,uuid[]) from public;
grant execute on function public.staff_sync_student_enrollments(uuid,uuid[]) to authenticated;
