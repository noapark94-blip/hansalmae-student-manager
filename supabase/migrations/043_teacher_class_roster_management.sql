-- 담당 클래스 화면에서 학생을 추가·제외합니다. 다른 클래스 수강과 과거 기록은 유지합니다.
create or replace function public.staff_sync_class_roster(
  p_class_id uuid,
  p_student_ids uuid[] default '{}'::uuid[]
)
returns void language plpgsql security definer set search_path=public as $$
declare requested_ids uuid[]:=coalesce(array(select distinct item from unnest(coalesce(p_student_ids,'{}'::uuid[])) as item),'{}'::uuid[]);
begin
  if not public.is_staff() then raise exception '교직원만 클래스 학생을 변경할 수 있습니다.'; end if;
  if not exists(select 1 from public.classes where id=p_class_id and active) then raise exception '운영 중인 클래스를 찾을 수 없습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스의 학생만 변경할 수 있습니다.'; end if;
  if exists(select 1 from unnest(requested_ids) requested_id left join public.students s on s.id=requested_id where s.id is null or s.status not in ('active','재원')) then raise exception '재원 상태인 학생만 배정할 수 있습니다.'; end if;

  update public.enrollments set status='completed',ended_on=current_date
  where class_id=p_class_id and status='active' and not(student_id=any(requested_ids));

  insert into public.enrollments(student_id,class_id,status,started_on)
  select requested_id,p_class_id,'active',current_date from unnest(requested_ids) requested_id
  where not exists(select 1 from public.enrollments e where e.student_id=requested_id and e.class_id=p_class_id and e.status='active')
  on conflict(student_id,class_id,started_on) do update set status='active',ended_on=null;
end $$;

revoke all on function public.staff_sync_class_roster(uuid,uuid[]) from public;
grant execute on function public.staff_sync_class_roster(uuid,uuid[]) to authenticated;
