
create or replace function public.student_assignment_version(p_student_id uuid) returns jsonb language sql stable security definer set search_path=public as $$
select jsonb_build_object('classes',coalesce((select jsonb_agg(x.class_id order by x.class_id) from (select distinct class_id from public.enrollments where student_id=p_student_id and status='active') x),'[]'::jsonb),'schedules',coalesce((select jsonb_agg(class_schedule_id order by class_schedule_id) from public.student_schedule_assignments where student_id=p_student_id),'[]'::jsonb))
$$;
revoke all on function public.student_assignment_version(uuid) from public,anon,authenticated;

create or replace function public.staff_student_assignment_plan(p_student_id uuid,p_class_ids uuid[]) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare chosen uuid[]:=coalesce(p_class_ids,'{}'); rows jsonb;
begin
if not coalesce(public.is_staff(),false) then raise exception '교직원만 수강 정보를 확인할 수 있습니다.'; end if;
if public.current_user_role()<>'admin' and (not coalesce(public.can_manage_student_schedule(p_student_id),false) or exists(select 1 from unnest(chosen) r(id) where not exists(select 1 from public.class_teachers where class_id=r.id and profile_id=auth.uid()))) then raise exception '담당 클래스만 배정할 수 있습니다.'; end if;
if exists(select 1 from unnest(chosen) r(id) where not exists(select 1 from public.classes where classes.id=r.id and active)) then raise exception '운영 중인 클래스를 선택해 주세요.'; end if;
select coalesce(jsonb_agg(jsonb_build_object('scheduleId',cs.id,'classId',c.id,'className',c.name,'subject',c.subject,'color',c.color,'weekday',cs.weekday,'startTime',cs.start_time,'endTime',cs.end_time,'assigned',
exists(select 1 from public.student_schedule_assignments s where s.student_id=p_student_id and s.class_schedule_id=cs.id) or not exists(select 1 from public.student_schedule_assignments s join public.class_schedules old on old.id=s.class_schedule_id where s.student_id=p_student_id and old.class_id=c.id)
) order by c.subject,cs.weekday,cs.start_time,c.name),'[]'::jsonb) into rows
from public.classes c join public.class_schedules cs on cs.class_id=c.id where c.id=any(chosen) and c.active and (cs.valid_from is null or cs.valid_from<=current_date) and (cs.valid_until is null or cs.valid_until>=current_date);
return jsonb_build_object('choices',rows,'base',public.student_assignment_version(p_student_id));
end $$;

create or replace function public.staff_save_student_assignment_plan(p_student_id uuid,p_class_ids uuid[],p_schedule_ids uuid[],p_base jsonb) returns void language plpgsql security definer set search_path=public as $$
declare chosen uuid[]:=coalesce(p_class_ids,'{}'); times uuid[]:=coalesce(p_schedule_ids,'{}'); cid uuid; keep_id uuid;
begin
perform public.staff_student_assignment_plan(p_student_id,chosen);
perform pg_advisory_xact_lock(hashtextextended('student_schedule:'||p_student_id::text,0));
if p_base is distinct from public.student_assignment_version(p_student_id) then raise exception '수강 배정이 변경됐습니다. 이전 화면으로 돌아가 최신 요일을 확인해 주세요.'; end if;
if not exists(select 1 from public.students where id=p_student_id) then raise exception '학생을 찾을 수 없습니다.'; end if;
if cardinality(times)<>(select count(distinct id) from unnest(times) id) then raise exception '중복된 수업 시간이 포함되어 있습니다.'; end if;
if exists(select 1 from unnest(times) r(id) where not exists(select 1 from public.class_schedules cs where cs.id=r.id and cs.class_id=any(chosen) and (cs.valid_from is null or cs.valid_from<=current_date) and (cs.valid_until is null or cs.valid_until>=current_date))) then raise exception '선택한 클래스의 현재 수업 시간만 저장할 수 있습니다.'; end if;
if exists(select 1 from unnest(chosen) r(id) where not exists(select 1 from public.class_schedules cs where cs.class_id=r.id and cs.id=any(times))) then raise exception '선택한 반마다 최소 한 개의 수업 요일을 선택해 주세요.'; end if;
if public.current_user_role()<>'admin' and exists(select 1 from public.enrollments e where e.student_id=p_student_id and e.status='active' and not(e.class_id=any(chosen)) and not exists(select 1 from public.class_teachers ct where ct.class_id=e.class_id and ct.profile_id=auth.uid())) then raise exception '다른 담당 선생님의 클래스는 제외할 수 없습니다.'; end if;
perform public.assert_student_schedule_selection_available(p_student_id,times);
update public.enrollments set status='completed',ended_on=current_date where student_id=p_student_id and status='active' and not(class_id=any(chosen));
for cid in select distinct id from unnest(chosen) id loop
select id into keep_id from public.enrollments where student_id=p_student_id and class_id=cid order by (status='active') desc,started_on desc,id limit 1;
if keep_id is null then insert into public.enrollments(student_id,class_id,status,started_on) values(p_student_id,cid,'active',current_date);
else
update public.enrollments set status='active',ended_on=null where id=keep_id;
update public.enrollments set status='completed',ended_on=coalesce(ended_on,current_date) where student_id=p_student_id and class_id=cid and id<>keep_id and status='active';
end if;
end loop;
delete from public.student_schedule_assignments where student_id=p_student_id;
insert into public.student_schedule_assignments(student_id,class_schedule_id,assigned_by) select p_student_id,id,auth.uid() from unnest(times) id;
end $$;
revoke all on function public.staff_student_assignment_plan(uuid,uuid[]),public.staff_save_student_assignment_plan(uuid,uuid[],uuid[],jsonb) from public,anon;
grant execute on function public.staff_student_assignment_plan(uuid,uuid[]),public.staff_save_student_assignment_plan(uuid,uuid[],uuid[],jsonb) to authenticated;
