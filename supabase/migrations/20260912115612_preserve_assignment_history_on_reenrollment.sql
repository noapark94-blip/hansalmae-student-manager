CREATE OR REPLACE FUNCTION public.staff_save_class_student_schedule_assignments(p_class_id uuid, p_student_id uuid, p_schedule_ids uuid[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare requested uuid[]:=coalesce(p_schedule_ids,'{}'::uuid[]); prospective uuid[]; keep_enrollment_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 수강 요일을 저장할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(
    select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()
  ) then raise exception '담당 클래스의 수강 요일만 설정할 수 있습니다.'; end if;
  if cardinality(requested)=0 then raise exception '최소 한 개의 수업 요일·시간을 선택해 주세요.'; end if;
  if cardinality(requested)<>(select count(distinct id) from unnest(requested) id) then raise exception '중복된 수업 시간이 포함되어 있습니다.'; end if;
  if exists(select 1 from unnest(requested) requested_id where not exists(
    select 1 from public.class_schedules cs where cs.id=requested_id and cs.class_id=p_class_id
      and (cs.valid_from is null or cs.valid_from<=current_date) and (cs.valid_until is null or cs.valid_until>=current_date)
  )) then raise exception '현재 이 클래스에 등록된 수업 시간만 선택할 수 있습니다.'; end if;

  perform pg_advisory_xact_lock(hashtextextended('student_schedule:'||p_student_id::text,0));
  select coalesce(array_agg(x.id),'{}'::uuid[]) into prospective from (
    select unnest(requested) id
    union
    select cs.id from public.enrollments e
    join public.classes c on c.id=e.class_id and c.active
    join public.class_schedules cs on cs.class_id=c.id
    where e.student_id=p_student_id and e.status='active' and e.class_id<>p_class_id
      and (cs.valid_from is null or cs.valid_from<=current_date) and (cs.valid_until is null or cs.valid_until>=current_date)
      and (not exists(select 1 from public.student_schedule_assignments where student_id=p_student_id)
        or exists(select 1 from public.student_schedule_assignments where student_id=p_student_id and class_schedule_id=cs.id))
  ) x;
  perform public.assert_student_schedule_selection_available(p_student_id,prospective);

  if not exists(select 1 from public.student_schedule_assignments where student_id=p_student_id) then
    insert into public.student_schedule_assignments(student_id,class_schedule_id,assigned_by)
    select p_student_id,cs.id,auth.uid() from public.enrollments e
    join public.classes c on c.id=e.class_id and c.active join public.class_schedules cs on cs.class_id=c.id
    where e.student_id=p_student_id and e.status='active' and e.class_id<>p_class_id
      and (cs.valid_from is null or cs.valid_from<=current_date) and (cs.valid_until is null or cs.valid_until>=current_date)
    on conflict do nothing;
  end if;
  delete from public.student_schedule_assignments ssa using public.class_schedules cs
  where ssa.class_schedule_id=cs.id and ssa.student_id=p_student_id and cs.class_id=p_class_id;
  insert into public.student_schedule_assignments(student_id,class_schedule_id,assigned_by)
  select p_student_id,id,auth.uid() from unnest(requested) id on conflict do nothing;

  select id into keep_enrollment_id from public.enrollments
  where student_id=p_student_id and class_id=p_class_id and (status='active' or started_on=current_date)
  order by (status='active') desc,started_on desc nulls last,id limit 1;
  if keep_enrollment_id is null then
    insert into public.enrollments(student_id,class_id,status,started_on) values(p_student_id,p_class_id,'active',current_date);
  else
    update public.enrollments set status='active',ended_on=null where id=keep_enrollment_id;
    update public.enrollments set status='completed',ended_on=coalesce(ended_on,current_date)
    where student_id=p_student_id and class_id=p_class_id and id<>keep_enrollment_id and status='active';
  end if;
end $function$
;
CREATE OR REPLACE FUNCTION public.staff_save_student_assignment_plan(p_student_id uuid, p_class_ids uuid[], p_schedule_ids uuid[], p_base jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare chosen uuid[]:=coalesce(p_class_ids,'{}'); times uuid[]:=coalesce(p_schedule_ids,'{}'); cid uuid; keep_id uuid;
begin
perform public.staff_student_assignment_plan(p_student_id,chosen);
perform pg_advisory_xact_lock(hashtextextended('student_schedule:'||p_student_id::text,0));
if p_base is distinct from public.student_assignment_version(p_student_id) then raise exception '수강 배정이 변경됐습니다. 창을 닫고 다시 열어 최신 배정을 확인해 주세요.'; end if;
if not exists(select 1 from public.students where id=p_student_id) then raise exception '학생을 찾을 수 없습니다.'; end if;
if cardinality(times)<>(select count(distinct id) from unnest(times) id) then raise exception '중복된 수업 시간이 포함되어 있습니다.'; end if;
if exists(select 1 from unnest(times) r(id) where not exists(select 1 from public.class_schedules cs where cs.id=r.id and cs.class_id=any(chosen) and (cs.valid_from is null or cs.valid_from<=current_date) and (cs.valid_until is null or cs.valid_until>=current_date))) then raise exception '선택한 클래스의 현재 수업 시간만 저장할 수 있습니다.'; end if;
if exists(select 1 from unnest(chosen) r(id) where not exists(select 1 from public.class_schedules cs where cs.class_id=r.id and cs.id=any(times))) then raise exception '선택한 반마다 최소 한 개의 수업 요일을 선택해 주세요.'; end if;
if public.current_user_role()<>'admin' and exists(select 1 from public.enrollments e where e.student_id=p_student_id and e.status='active' and not(e.class_id=any(chosen)) and not exists(select 1 from public.class_teachers ct where ct.class_id=e.class_id and ct.profile_id=auth.uid())) then raise exception '다른 담당 선생님의 클래스는 제외할 수 없습니다.'; end if;
perform public.assert_student_schedule_selection_available(p_student_id,times);
update public.enrollments set status='completed',ended_on=current_date where student_id=p_student_id and status='active' and not(class_id=any(chosen));
for cid in select distinct id from unnest(chosen) id loop
select id into keep_id from public.enrollments where student_id=p_student_id and class_id=cid and (status='active' or started_on=current_date) order by (status='active') desc,started_on desc,id limit 1;
if keep_id is null then insert into public.enrollments(student_id,class_id,status,started_on) values(p_student_id,cid,'active',current_date);
else
update public.enrollments set status='active',ended_on=null where id=keep_id;
update public.enrollments set status='completed',ended_on=coalesce(ended_on,current_date) where student_id=p_student_id and class_id=cid and id<>keep_id and status='active';
end if;
end loop;
delete from public.student_schedule_assignments where student_id=p_student_id;
insert into public.student_schedule_assignments(student_id,class_schedule_id,assigned_by) select p_student_id,id,auth.uid() from unnest(times) id;
end $function$
;
