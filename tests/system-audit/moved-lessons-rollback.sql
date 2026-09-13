begin;
do $test$
declare sid uuid; gid uuid; cid uuid; schedule_id uuid; lid uuid; exception_id uuid; tdate date:=(now() at time zone 'Asia/Seoul')::date; rows jsonb;
begin
select sg.student_id,g.profile_id into sid,gid from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id join public.profiles p on p.id=g.profile_id and p.is_active limit 1;
if sid is null then raise exception 'guardian fixture required'; end if;
insert into public.classes(name,subject) values('rollback moved class '||gen_random_uuid(),'수학') returning id into cid;
insert into public.class_schedules(class_id,weekday,start_time,end_time) values(cid,extract(isodow from tdate-1)::smallint,'15:00','16:00') returning id into schedule_id;
insert into public.enrollments(student_id,class_id,status,started_on) values(sid,cid,'active',tdate-10);
insert into public.student_schedule_assignments(student_id,class_schedule_id) values(sid,schedule_id);
insert into public.lessons(class_id,lesson_date,starts_at,ends_at,status) values(cid,tdate,(tdate+time '15:00') at time zone 'Asia/Seoul',(tdate+time '16:00') at time zone 'Asia/Seoul','scheduled') returning id into lid;
perform set_config('request.jwt.claim.sub',gid::text,true);
rows:=public.family_today_lessons(sid);
if exists(select 1 from jsonb_array_elements(rows) x where x->>'id'='regular:'||lid) then raise exception 'unassigned weekday leaked'; end if;
insert into public.schedule_exceptions(class_id,original_date,kind,replacement_date,start_time,end_time) values(cid,tdate-1,'changed',tdate,'15:00','16:00') returning id into exception_id;
rows:=public.family_today_lessons(sid);
if not exists(select 1 from jsonb_array_elements(rows) x where x->>'id'='regular:'||lid) then raise exception 'moved lesson missing'; end if;
update public.lessons set status='cancelled' where id=lid;
rows:=public.family_today_lessons(sid);
if exists(select 1 from jsonb_array_elements(rows) x where x->>'id'='regular:'||lid) then raise exception 'cancelled lesson leaked'; end if;
-- Completed attendance remains reportable after the class enrollment ends.
perform set_config('request.jwt.claim.sub',(select id::text from public.profiles where role='admin' and is_active limit 1),true);
update public.lessons set status='completed' where id=lid;
insert into public.attendance(lesson_id,student_id,status) values(lid,sid,'present');
delete from public.enrollments where class_id=cid and student_id=sid;
rows:=public.staff_learning_report_source(sid,tdate,tdate);
if not exists(select 1 from jsonb_array_elements(rows) x where x->>'lessonId'=lid::text) then raise exception 'completed source lost attendance'; end if;
rows:=public.staff_alimtalk_ready_students(tdate,tdate);
if not exists(select 1 from jsonb_array_elements(rows) r cross join lateral jsonb_array_elements(r->'lessons') x where r->>'studentId'=sid::text and x->>'lessonId'=lid::text) then raise exception 'completed unscheduled record missing in send list'; end if;
end $test$;
select 'PASS moved/cancelled visibility and completed record without enrollment' result;
rollback;
