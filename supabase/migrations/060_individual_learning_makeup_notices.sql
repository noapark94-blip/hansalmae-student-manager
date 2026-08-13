-- 공통 수업 기록 대신 학생별 시험·숙제와 반 공지, 날짜별 보충 참석을 관리합니다.

alter table public.lesson_exam_results add column if not exists exam_type text;
alter table public.lesson_exam_results add column if not exists exam_title text;
alter table public.lesson_homework_results add column if not exists assigned_homework text;
alter table public.lesson_homework_results add column if not exists inspection_status text;
alter table public.lesson_homework_results add column if not exists inspection_note text;

create table if not exists public.class_daily_notices (
  id uuid primary key default gen_random_uuid(),
  class_id uuid not null references public.classes(id) on delete cascade,
  notice_date date not null,
  content text not null,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(class_id,notice_date)
);

create table if not exists public.class_makeup_attendees (
  class_id uuid not null references public.classes(id) on delete cascade,
  attendance_date date not null,
  student_id uuid not null references public.students(id) on delete cascade,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key(class_id,attendance_date,student_id)
);

alter table public.class_daily_notices enable row level security;
alter table public.class_makeup_attendees enable row level security;

create policy "staff_manage_class_daily_notices" on public.class_daily_notices for all to authenticated
using (public.current_user_role()='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=class_daily_notices.class_id and ct.profile_id=auth.uid()))
with check (public.current_user_role()='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=class_daily_notices.class_id and ct.profile_id=auth.uid()));
create policy "staff_manage_class_makeup_attendees" on public.class_makeup_attendees for all to authenticated
using (public.current_user_role()='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=class_makeup_attendees.class_id and ct.profile_id=auth.uid()))
with check (public.current_user_role()='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=class_makeup_attendees.class_id and ct.profile_id=auth.uid()));

create or replace function public.student_attends_class_on(p_student_id uuid,p_class_id uuid,p_date date)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.class_makeup_attendees m where m.student_id=p_student_id and m.class_id=p_class_id and m.attendance_date=p_date)
  or case when exists(select 1 from public.student_schedule_assignments where student_id=p_student_id)
    then exists(select 1 from public.student_schedule_assignments ssa join public.class_schedules cs on cs.id=ssa.class_schedule_id
      where ssa.student_id=p_student_id and cs.class_id=p_class_id and cs.weekday=extract(isodow from p_date)::smallint)
    else exists(select 1 from public.enrollments e where e.student_id=p_student_id and e.class_id=p_class_id and e.status='active'
      and e.started_on<=p_date and (e.ended_on is null or e.ended_on>=p_date)) end;
$$;

create or replace function public.staff_class_makeup_options(p_class_id uuid,p_date date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception '교직원만 보충 학생을 관리할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 관리할 수 있습니다.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade,'selected',m.student_id is not null) order by s.name)
    from public.enrollments e join public.students s on s.id=e.student_id
    left join public.class_makeup_attendees m on m.class_id=p_class_id and m.attendance_date=p_date and m.student_id=s.id
    where e.class_id=p_class_id and e.status='active' and e.started_on<=p_date and (e.ended_on is null or e.ended_on>=p_date)),'[]'::jsonb);
end $$;

create or replace function public.staff_save_class_makeup_students(p_class_id uuid,p_date date,p_student_ids uuid[])
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception '교직원만 보충 학생을 관리할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 관리할 수 있습니다.'; end if;
  if exists(select 1 from unnest(coalesce(p_student_ids,'{}')) sid where not exists(select 1 from public.enrollments e where e.class_id=p_class_id and e.student_id=sid and e.status='active')) then raise exception '현재 수강생만 보충 수업에 추가할 수 있습니다.'; end if;
  delete from public.class_makeup_attendees where class_id=p_class_id and attendance_date=p_date;
  insert into public.class_makeup_attendees(class_id,attendance_date,student_id,created_by)
  select p_class_id,p_date,sid,auth.uid() from unnest(coalesce(p_student_ids,'{}')) sid;
end $$;

create or replace function public.staff_save_class_day(p_class_id uuid,p_date date,p_exam_content text,p_lesson_content text,p_homework_content text)
returns uuid language plpgsql security definer set search_path=public as $$
declare schedule_row public.class_schedules; result_id uuid; v_start time; v_end time;
begin
  if not public.is_staff() then raise exception '교직원만 수업 기록을 저장할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 수정할 수 있습니다.'; end if;
  select * into schedule_row from public.class_schedules where class_id=p_class_id and weekday=extract(isodow from p_date)::smallint and (valid_from is null or valid_from<=p_date) and (valid_until is null or valid_until>=p_date) order by start_time limit 1;
  if schedule_row.id is null and not exists(select 1 from public.class_makeup_attendees where class_id=p_class_id and attendance_date=p_date) then raise exception '정규 수업이 없는 날짜입니다. 보충 학생을 먼저 추가해 주세요.'; end if;
  v_start:=coalesce(schedule_row.start_time,'18:00'::time); v_end:=coalesce(schedule_row.end_time,'20:00'::time);
  insert into public.lessons(class_id,lesson_date,starts_at,ends_at,room,teacher_profile_id,updated_at)
  select c.id,p_date,((p_date+v_start) at time zone 'Asia/Seoul'),((p_date+v_end) at time zone 'Asia/Seoul'),c.room,auth.uid(),now() from public.classes c where c.id=p_class_id
  on conflict(class_id,starts_at) do update set teacher_profile_id=auth.uid(),updated_at=now()
  returning id into result_id;
  return result_id;
end $$;

create or replace function public.staff_class_day(p_class_id uuid,p_date date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 수업 기록을 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  select jsonb_build_object('lessonId',l.id,'examContent',null,'lessonContent',null,'homeworkContent',null,
    'students',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade,'status',a.status,'lateMinutes',a.late_minutes,'absenceReason',a.absence_reason,'note',a.note) order by s.name)
      from public.enrollments e join public.students s on s.id=e.student_id left join public.attendance a on a.student_id=s.id and a.lesson_id=l.id
      where e.class_id=p_class_id and e.status='active' and public.student_attends_class_on(s.id,p_class_id,p_date)),'[]'::jsonb))
  into result from public.classes c left join public.lessons l on l.class_id=c.id and l.lesson_date=p_date where c.id=p_class_id;
  return coalesce(result,jsonb_build_object('lessonId',null,'examContent',null,'lessonContent',null,'homeworkContent',null,'students','[]'::jsonb));
end $$;

create or replace function public.staff_class_daily_notice(p_class_id uuid,p_date date)
returns text language plpgsql stable security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception '교직원만 반 공지를 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  return (select content from public.class_daily_notices where class_id=p_class_id and notice_date=p_date);
end $$;

create or replace function public.staff_save_class_daily_notice(p_class_id uuid,p_date date,p_content text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception '교직원만 반 공지를 저장할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 수정할 수 있습니다.'; end if;
  if nullif(trim(p_content),'') is null then delete from public.class_daily_notices where class_id=p_class_id and notice_date=p_date;
  else insert into public.class_daily_notices(class_id,notice_date,content,created_by) values(p_class_id,p_date,trim(p_content),auth.uid())
    on conflict(class_id,notice_date) do update set content=excluded.content,created_by=auth.uid(),updated_at=now(); end if;
end $$;

create or replace function public.staff_class_exam_results(p_class_id uuid,p_date date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 시험 결과를 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('studentId',s.id,'studentName',s.name,'school',s.school,'grade',s.grade,'examType',coalesce(r.exam_type,''),'examTitle',coalesce(r.exam_title,''),'score',r.score,'maxScore',coalesce(r.max_score,100),'evaluation',coalesce(r.evaluation,''),'feedback',coalesce(r.feedback,'')) order by s.name),'[]'::jsonb) into result
  from public.enrollments e join public.students s on s.id=e.student_id
  left join lateral(select id from public.lessons where class_id=p_class_id and lesson_date=p_date order by starts_at limit 1) l on true
  left join public.lesson_exam_results r on r.lesson_id=l.id and r.student_id=s.id
  where e.class_id=p_class_id and e.status='active' and public.student_attends_class_on(s.id,p_class_id,p_date);
  return result;
end $$;

create or replace function public.staff_save_class_exam_results(p_class_id uuid,p_date date,p_results jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare lesson uuid; item jsonb; sid uuid; score_value numeric; max_value numeric; kind text; title_value text; evaluation_value text; feedback_value text;
begin
  lesson:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  for item in select value from jsonb_array_elements(coalesce(p_results,'[]'::jsonb)) loop
    sid:=(item->>'studentId')::uuid; score_value:=nullif(item->>'score','')::numeric; max_value:=coalesce(nullif(item->>'maxScore','')::numeric,100);
    kind:=nullif(trim(item->>'examType'),''); title_value:=nullif(trim(item->>'examTitle'),''); evaluation_value:=nullif(trim(item->>'evaluation'),''); feedback_value:=nullif(trim(item->>'feedback'),'');
    if max_value<=0 or (score_value is not null and (score_value<0 or score_value>max_value)) then raise exception '점수와 만점을 확인해 주세요.'; end if;
    if kind is null and title_value is null and score_value is null and evaluation_value is null and feedback_value is null then delete from public.lesson_exam_results where lesson_id=lesson and student_id=sid;
    else insert into public.lesson_exam_results(lesson_id,student_id,exam_type,exam_title,score,max_score,evaluation,feedback,created_by) values(lesson,sid,kind,title_value,score_value,max_value,evaluation_value,feedback_value,auth.uid())
      on conflict(lesson_id,student_id) do update set exam_type=excluded.exam_type,exam_title=excluded.exam_title,score=excluded.score,max_score=excluded.max_score,evaluation=excluded.evaluation,feedback=excluded.feedback,updated_at=now(); end if;
  end loop;
end $$;

create or replace function public.staff_class_homework_results(p_class_id uuid,p_date date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 숙제 결과를 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('studentId',s.id,'assignedHomework',coalesce(current_result.assigned_homework,''),'inspectionStatus',coalesce(current_result.inspection_status,current_result.status,''),'inspectionNote',coalesce(current_result.inspection_note,current_result.note,''),'previousHomework',coalesce(previous_result.assigned_homework,'')) order by s.name),'[]'::jsonb) into result
  from public.enrollments e join public.students s on s.id=e.student_id
  left join lateral(select id from public.lessons where class_id=p_class_id and lesson_date=p_date order by starts_at limit 1) lesson on true
  left join public.lesson_homework_results current_result on current_result.lesson_id=lesson.id and current_result.student_id=s.id
  left join lateral(select hr.assigned_homework from public.lesson_homework_results hr join public.lessons prior on prior.id=hr.lesson_id where prior.class_id=p_class_id and prior.lesson_date<p_date and hr.student_id=s.id and nullif(trim(hr.assigned_homework),'') is not null order by prior.lesson_date desc limit 1) previous_result on true
  where e.class_id=p_class_id and e.status='active' and public.student_attends_class_on(s.id,p_class_id,p_date);
  return result;
end $$;

create or replace function public.staff_save_class_homework_results(p_class_id uuid,p_date date,p_results jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare lesson uuid; item jsonb; sid uuid; assigned text; inspection text; inspection_memo text;
begin
  lesson:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  for item in select value from jsonb_array_elements(coalesce(p_results,'[]'::jsonb)) loop
    sid:=(item->>'studentId')::uuid; assigned:=nullif(trim(item->>'assignedHomework'),''); inspection:=nullif(item->>'inspectionStatus',''); inspection_memo:=nullif(trim(item->>'inspectionNote'),'');
    if inspection is not null and inspection not in ('complete','partial','missing','excused') then raise exception '숙제 검사 상태를 확인해 주세요.'; end if;
    if assigned is null and inspection is null and inspection_memo is null then delete from public.lesson_homework_results where lesson_id=lesson and student_id=sid;
    else insert into public.lesson_homework_results(lesson_id,student_id,assigned_homework,inspection_status,inspection_note,status,note,created_by) values(lesson,sid,assigned,inspection,inspection_memo,inspection,inspection_memo,auth.uid())
      on conflict(lesson_id,student_id) do update set assigned_homework=excluded.assigned_homework,inspection_status=excluded.inspection_status,inspection_note=excluded.inspection_note,status=excluded.status,note=excluded.note,updated_at=now(); end if;
  end loop;
end $$;

revoke all on function public.staff_class_makeup_options(uuid,date),public.staff_save_class_makeup_students(uuid,date,uuid[]),public.staff_class_daily_notice(uuid,date),public.staff_save_class_daily_notice(uuid,date,text) from public;
grant execute on function public.staff_class_makeup_options(uuid,date),public.staff_save_class_makeup_students(uuid,date,uuid[]),public.staff_class_daily_notice(uuid,date),public.staff_save_class_daily_notice(uuid,date,text) to authenticated;
grant select,insert,update,delete on public.class_daily_notices,public.class_makeup_attendees to authenticated;

-- 학생 배정 화면에서 현재 반과 같은 과목을 먼저 추천할 수 있도록 수강 클래스 정보도 제공합니다.
create or replace function public.staff_student_roster()
returns table (id uuid,name text,school text,grade text,status text,enrollments jsonb)
language sql stable security definer set search_path=public as $$
  select s.id,s.name,s.school,s.grade,s.status,
    coalesce(jsonb_agg(jsonb_build_object(
      'class_id',e.class_id,
      'status',e.status,
      'classes',jsonb_build_object('name',c.name,'subject',c.subject)
    )) filter(where e.id is not null),'[]'::jsonb)
  from public.students s
  left join public.enrollments e on e.student_id=s.id
  left join public.classes c on c.id=e.class_id
  where public.is_staff()
  group by s.id,s.name,s.school,s.grade,s.status
  order by s.name
$$;
revoke all on function public.staff_student_roster() from public;
grant execute on function public.staff_student_roster() to authenticated;
notify pgrst,'reload schema';
