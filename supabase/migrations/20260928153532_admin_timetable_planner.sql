-- Administrator-only planning drafts. No production timetable is modified by saving.
create table public.timetable_plans (
 id uuid primary key default gen_random_uuid(), title text not null check(length(title) between 1 and 100),
 starts_on date not null, payload jsonb not null, version integer not null default 1,
 applied_at timestamptz, created_by uuid not null references public.profiles(id), updated_at timestamptz not null default now()
);
alter table public.timetable_plans enable row level security;
revoke all on public.timetable_plans from public,anon,authenticated;
grant select on public.timetable_plans to authenticated;
create policy planner_admin_read on public.timetable_plans for select to authenticated using((select public.current_user_role())='admin');

create function public.admin_timetable_source() returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
 if auth.uid() is null or public.current_user_role() is distinct from 'admin' then raise exception '관리자만 시간표를 편성할 수 있습니다.'; end if;
 select jsonb_build_object(
 'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'subject',c.subject,'room',coalesce(c.room,''),'teachers',coalesce((select jsonb_agg(ct.profile_id order by ct.profile_id) from class_teachers ct where ct.class_id=c.id),'[]'::jsonb),'students',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'grade',coalesce(s.grade,'')) order by s.id) from enrollments e join students s on s.id=e.student_id where e.class_id=c.id and e.status='active' and s.status in ('active','재원')),'[]'::jsonb)) order by c.id) from classes c where c.active),'[]'::jsonb),
 'teachers',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.id) from profiles p where exists(select 1 from class_teachers ct where ct.profile_id=p.id)),'[]'::jsonb),
 'schedules',coalesce((select jsonb_agg(to_jsonb(s) order by s.id) from class_schedules s),'[]'::jsonb),
 'assignments',coalesce((select jsonb_agg(to_jsonb(a) order by a.student_id,a.class_schedule_id) from student_schedule_assignments a),'[]'::jsonb)
 ) into result;
 return result || jsonb_build_object('version',md5(result::text));
end $$;

create function public.admin_save_timetable_plan(p_id uuid,p_title text,p_starts_on date,p_payload jsonb,p_version integer default null) returns jsonb language plpgsql security definer set search_path=public as $$
declare r timetable_plans;
begin
 if auth.uid() is null or current_user_role() is distinct from 'admin' then raise exception '관리자만 저장할 수 있습니다.'; end if;
 if jsonb_typeof(p_payload) is distinct from 'object' or octet_length(p_payload::text)>2000000 then raise exception '초안 형식을 확인해 주세요.'; end if;
 if jsonb_typeof(p_payload->'config'->'courses') is distinct from 'array' or jsonb_typeof(p_payload->'config'->'teachers') is distinct from 'array' or jsonb_typeof(p_payload->'config'->'starts') is distinct from 'array' or jsonb_typeof(p_payload->'meetings') is distinct from 'array' or p_payload->>'sourceVersion' is null then raise exception '초안 내용이 올바르지 않습니다.'; end if;
 if p_id is null then insert into timetable_plans(title,starts_on,payload,created_by) values(trim(p_title),p_starts_on,p_payload,auth.uid()) returning * into r;
 else update timetable_plans set title=trim(p_title),starts_on=p_starts_on,payload=p_payload,version=version+1,updated_at=now() where id=p_id and version=p_version and applied_at is null returning * into r;
 if not found then raise exception '다른 관리자가 수정했거나 이미 적용한 초안입니다. 다시 불러와 주세요.'; end if; end if;
 return to_jsonb(r);
end $$;

create function public.admin_apply_timetable_plan(p_id uuid,p_version integer) returns jsonb language plpgsql security definer set search_path=public as $$
declare r timetable_plans; source jsonb; course jsonb; m jsonb; n integer; ids uuid[];
begin
 if auth.uid() is null or current_user_role() is distinct from 'admin' then raise exception '관리자만 적용할 수 있습니다.'; end if;
 -- Lock all scheduling inputs during validation and versioned replacement.
 lock table classes,class_teachers,class_schedules,enrollments,student_schedule_assignments,students,lessons,teacher_special_lessons,teacher_special_lesson_students,schedule_exceptions in share row exclusive mode;
 select * into r from timetable_plans where id=p_id for update;
 if not found or r.version<>p_version or r.applied_at is not null then raise exception '초안이 변경되었거나 이미 적용되었습니다.'; end if;
 if r.starts_on<=(now() at time zone 'Asia/Seoul')::date then raise exception '적용일은 내일 이후로 선택해 주세요.'; end if;
 source:=admin_timetable_source();
 if source->>'version' is distinct from r.payload->>'sourceVersion' then raise exception '클래스·수강생·시간표가 변경되었습니다. 최신 정보로 새 초안을 만들어 주세요.'; end if;
 if jsonb_typeof(r.payload->'meetings') is distinct from 'array' or jsonb_array_length(r.payload->'meetings')=0 then raise exception '적용할 후보를 선택해 주세요.'; end if;
 select array_agg((x->>'id')::uuid) into ids from jsonb_array_elements(r.payload->'config'->'courses') x where (x->>'enabled')::boolean;
 if ids is null then raise exception '클래스를 선택해 주세요.'; end if;
 if exists(select 1 from class_schedules s join student_schedule_assignments a on a.class_schedule_id=s.id where s.class_id=any(ids)) then raise exception '요일별 개별 수강 배정이 있는 클래스입니다. 개별 배정을 먼저 정리한 후 적용해 주세요.'; end if;
 if exists(select 1 from lessons where class_id=any(ids) and lesson_date>=r.starts_on) or exists(select 1 from schedule_exceptions where class_id=any(ids) and (original_date>=r.starts_on or replacement_date>=r.starts_on)) then raise exception '적용일 이후 저장된 수업이나 변경·보강 일정이 있습니다. 해당 일정을 먼저 확인해 주세요.'; end if;
 if exists(select 1 from class_schedules where class_id=any(ids) and valid_from>=r.starts_on) then raise exception '이미 예약된 미래 시간표가 있습니다. 먼저 확인해 주세요.'; end if;
 for course in select x from jsonb_array_elements(r.payload->'config'->'courses') x where (x->>'enabled')::boolean loop
  if not exists(select 1 from classes where id=(course->>'id')::uuid and active) then raise exception '활성 클래스를 확인해 주세요.'; end if;
  select count(*) into n from jsonb_array_elements(r.payload->'meetings') x where x->>'classId'=course->>'id';
  if course->>'count' is null or course->>'duration' is null or n<>(course->>'count')::integer or n not between 1 and 7 or (course->>'duration')::integer not between 30 and 240 then raise exception '주당 횟수 또는 수업 길이가 올바르지 않습니다.'; end if;
 end loop;
 for m in select x from jsonb_array_elements(r.payload->'meetings') x loop
  if not (m ?& array['classId','day','start','end']) or m->>'classId' is null or m->>'day' is null or m->>'start' is null or m->>'end' is null or not ((m->>'classId')::uuid=any(ids)) or (m->>'day')::integer not between 1 and 7 or (m->>'start')::integer<0 or (m->>'end')::integer>1320 or (m->>'end')::integer<=(m->>'start')::integer then raise exception '수업 시간 형식이 올바르지 않습니다.'; end if;
  select x into course from jsonb_array_elements(r.payload->'config'->'courses') x where x->>'id'=m->>'classId';
  if (m->>'end')::integer-(m->>'start')::integer<>(course->>'duration')::integer then raise exception '설정한 수업 길이와 일치하지 않습니다.'; end if;
  if not exists(select 1 from class_teachers where class_id=(m->>'classId')::uuid) then raise exception '담당 선생님이 없는 클래스가 있습니다.'; end if;
  if exists(select 1 from class_teachers ct where ct.class_id=(m->>'classId')::uuid and not exists(select 1 from jsonb_array_elements(r.payload->'config'->'teachers') t where t->>'id'=ct.profile_id::text and t->'days' @> jsonb_build_array((m->>'day')::integer))) then raise exception '선생님 근무 요일을 벗어난 수업입니다.'; end if;
  if not exists(select 1 from unnest(string_to_array(r.payload->'config'->'starts'->>((m->>'day')::integer-1),',')) t where trim(t)=to_char(time '00:00'+(m->>'start')::integer*interval '1 minute','HH24:MI')) then raise exception '허용한 시작 시간이 아닙니다.'; end if;
  if (m->>'day')::integer<=5 and (m->>'start')::integer < (case when (m->>'day')::integer in (2,4) or coalesce((course->>'high')::boolean,false) then 1020 else 960 end) then raise exception '학년별 수업 가능 시간을 확인해 주세요.'; end if;

 end loop;
 -- Proposed rows plus unchanged classes, checked using current teacher/student data.
 if exists(
 with proposed as (select (x->>'classId')::uuid cid,(x->>'day')::int as weekday,(x->>'start')::int st,(x->>'end')::int en,true changed from jsonb_array_elements(r.payload->'meetings') x),
 all_rows as (select * from proposed union all select s.class_id,s.weekday,extract(epoch from s.start_time)::int/60,extract(epoch from s.end_time)::int/60,false from class_schedules s join classes c on c.id=s.class_id where c.active and not(s.class_id=any(ids)) and (s.valid_until is null or s.valid_until>=r.starts_on))
 select 1 from proposed a join all_rows b on a.weekday=b.weekday and a.st<b.en and b.st<a.en and (a.cid<>b.cid or a.st<>b.st or a.en<>b.en)
 join classes ca on ca.id=a.cid join classes cb on cb.id=b.cid
 where a.cid=b.cid or (nullif(regexp_replace(ca.room,'\s','','g'),'')=nullif(regexp_replace(cb.room,'\s','','g'),''))
 or exists(select 1 from class_teachers ta join class_teachers tb on ta.profile_id=tb.profile_id where ta.class_id=a.cid and tb.class_id=b.cid)
 or exists(select 1 from enrollments ea join enrollments eb on ea.student_id=eb.student_id join students s on s.id=ea.student_id where ea.class_id=a.cid and eb.class_id=b.cid and ea.status='active' and eb.status='active' and s.status in ('active','재원'))
 ) then raise exception '기존 또는 새 시간표에 학생·선생님·강의실 충돌이 있습니다.'; end if;
 if exists(select 1 from jsonb_array_elements(r.payload->'meetings') x group by x->>'classId',x->>'day' having count(*)>1) then raise exception '같은 클래스가 하루에 여러 번 배정되어 있습니다.'; end if;
 -- Conservatively block future special lessons involving affected teachers/students.
 if exists(select 1 from teacher_special_lessons l where l.lesson_date>=r.starts_on and (exists(select 1 from class_teachers ct where ct.class_id=any(ids) and ct.profile_id=l.teacher_profile_id) or exists(select 1 from teacher_special_lesson_students ss join enrollments e on e.student_id=ss.student_id where ss.session_id=l.id and e.class_id=any(ids) and e.status='active'))) then raise exception '관련 선생님·학생의 보강·추가수업이 예약되어 있습니다. 일정을 확인한 뒤 적용해 주세요.'; end if;
 update class_schedules set valid_until=r.starts_on-1 where class_id=any(ids) and (valid_until is null or valid_until>=r.starts_on);
 for m in select x from jsonb_array_elements(r.payload->'meetings') x loop
 insert into class_schedules(class_id,weekday,start_time,end_time,valid_from) values((m->>'classId')::uuid,(m->>'day')::smallint,time '00:00'+(m->>'start')::int*interval '1 minute',time '00:00'+(m->>'end')::int*interval '1 minute',r.starts_on);
 end loop;
 update timetable_plans set applied_at=now(),version=version+1,updated_at=now() where id=r.id returning * into r;
 return to_jsonb(r);
end $$;
revoke all on function public.admin_timetable_source(),public.admin_save_timetable_plan(uuid,text,date,jsonb,integer),public.admin_apply_timetable_plan(uuid,integer) from public,anon;
grant execute on function public.admin_timetable_source(),public.admin_save_timetable_plan(uuid,text,date,jsonb,integer),public.admin_apply_timetable_plan(uuid,integer) to authenticated;
