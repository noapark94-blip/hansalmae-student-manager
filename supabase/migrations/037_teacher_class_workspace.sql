-- 학생 한 명을 여러 과목/클래스에 연결하고, 선생님별 수업 운영 화면을 제공합니다.

create table public.academy_subjects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  main_subject text not null check (main_subject in ('국어','영어','수학')),
  parent_id uuid references public.academy_subjects(id) on delete restrict,
  created_by uuid references public.profiles(id) on delete set null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (main_subject, name)
);

insert into public.academy_subjects(name,main_subject)
values ('국어','국어'),('영어','영어'),('수학','수학')
on conflict do nothing;

alter table public.classes add column subject_id uuid references public.academy_subjects(id) on delete set null;
update public.classes c set subject_id=s.id from public.academy_subjects s
where s.name=case when c.subject like '%국%' then '국어' when c.subject like '%영%' then '영어' when c.subject like '%수%' then '수학' end
  and c.subject_id is null;

alter table public.lessons add column exam_content text;
alter table public.lessons add column lesson_content text;
alter table public.lessons add column homework_content text;
alter table public.lessons add column teacher_profile_id uuid references public.profiles(id) on delete set null;
alter table public.lessons add column updated_at timestamptz not null default now();
alter table public.attendance add column late_minutes integer check (late_minutes is null or late_minutes between 1 and 300);
alter table public.attendance add column absence_reason text;

alter table public.academy_subjects enable row level security;
create policy "authenticated_read_subjects" on public.academy_subjects for select to authenticated using (active or public.is_staff());
create policy "staff_manage_subjects" on public.academy_subjects for all to authenticated using (public.is_staff()) with check (public.is_staff());
grant select,insert,update on public.academy_subjects to authenticated;

create or replace function public.staff_create_subject(p_main_subject text,p_name text)
returns uuid language plpgsql security definer set search_path=public as $$
declare parent_subject public.academy_subjects; result_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 과목을 추가할 수 있습니다.'; end if;
  if p_main_subject not in ('국어','영어','수학') then raise exception '기본 과목은 국어, 영어, 수학 중에서 선택해 주세요.'; end if;
  if nullif(trim(p_name),'') is null then raise exception '하위과목 이름을 입력해 주세요.'; end if;
  select * into parent_subject from public.academy_subjects where name=p_main_subject and main_subject=p_main_subject and parent_id is null;
  insert into public.academy_subjects(name,main_subject,parent_id,created_by)
  values(trim(p_name),p_main_subject,case when trim(p_name)=p_main_subject then null else parent_subject.id end,auth.uid())
  on conflict(main_subject,name) do update set active=true
  returning id into result_id;
  return result_id;
end $$;

create or replace function public.teacher_class_workspace()
returns jsonb language sql stable security definer set search_path=public as $$
  select case when public.is_staff() then jsonb_build_object(
    'subjects',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'mainSubject',s.main_subject,'parentId',s.parent_id) order by case s.main_subject when '국어' then 1 when '영어' then 2 else 3 end,s.parent_id nulls first,s.name) from public.academy_subjects s where s.active),'[]'::jsonb),
    'classes',coalesce((select jsonb_agg(jsonb_build_object(
      'id',c.id,'name',c.name,'subject',c.subject,'subjectId',c.subject_id,'room',c.room,'color',c.color,
      'schedules',coalesce((select jsonb_agg(jsonb_build_object('id',cs.id,'weekday',cs.weekday,'startTime',cs.start_time,'endTime',cs.end_time) order by cs.weekday,cs.start_time) from public.class_schedules cs where cs.class_id=c.id and (cs.valid_until is null or cs.valid_until>=current_date)),'[]'::jsonb),
      'students',coalesce((select jsonb_agg(jsonb_build_object('id',st.id,'name',st.name,'school',st.school,'grade',st.grade) order by st.name) from public.enrollments e join public.students st on st.id=e.student_id where e.class_id=c.id and e.status='active'),'[]'::jsonb)
    ) order by c.subject,c.name) from public.classes c where c.active and (public.current_user_role()='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid()))),'[]'::jsonb)
  ) else null end
$$;

create or replace function public.staff_class_day(p_class_id uuid,p_date date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 수업 기록을 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  select jsonb_build_object(
    'lessonId',l.id,'examContent',l.exam_content,'lessonContent',l.lesson_content,'homeworkContent',l.homework_content,
    'students',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'status',a.status,'lateMinutes',a.late_minutes,'absenceReason',a.absence_reason,'note',a.note) order by s.name)
      from public.enrollments e join public.students s on s.id=e.student_id left join public.attendance a on a.student_id=s.id and a.lesson_id=l.id
      where e.class_id=p_class_id and e.status='active' and e.started_on<=p_date and (e.ended_on is null or e.ended_on>=p_date)),'[]'::jsonb)
  ) into result from public.classes c left join public.lessons l on l.class_id=c.id and l.lesson_date=p_date where c.id=p_class_id;
  return coalesce(result,jsonb_build_object('lessonId',null,'examContent',null,'lessonContent',null,'homeworkContent',null,'students','[]'::jsonb));
end $$;

create or replace function public.staff_save_class_day(
  p_class_id uuid,p_date date,p_exam_content text,p_lesson_content text,p_homework_content text
) returns uuid language plpgsql security definer set search_path=public as $$
declare schedule_row public.class_schedules; result_id uuid;
begin
  if not public.is_staff() then raise exception '교직원만 수업 기록을 저장할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 수정할 수 있습니다.'; end if;
  select * into schedule_row from public.class_schedules where class_id=p_class_id and weekday=extract(isodow from p_date)::smallint and (valid_from is null or valid_from<=p_date) and (valid_until is null or valid_until>=p_date) order by start_time limit 1;
  if schedule_row.id is null then raise exception '선택한 날짜에 이 클래스 수업 시간이 없습니다.'; end if;
  insert into public.lessons(class_id,lesson_date,starts_at,ends_at,room,exam_content,lesson_content,homework_content,teacher_profile_id,updated_at)
  select c.id,p_date,((p_date+schedule_row.start_time) at time zone 'Asia/Seoul'),((p_date+schedule_row.end_time) at time zone 'Asia/Seoul'),c.room,nullif(trim(p_exam_content),''),nullif(trim(p_lesson_content),''),nullif(trim(p_homework_content),''),auth.uid(),now() from public.classes c where c.id=p_class_id
  on conflict(class_id,starts_at) do update set exam_content=coalesce(excluded.exam_content,lessons.exam_content),lesson_content=coalesce(excluded.lesson_content,lessons.lesson_content),homework_content=coalesce(excluded.homework_content,lessons.homework_content),teacher_profile_id=auth.uid(),updated_at=now()
  returning id into result_id;
  return result_id;
end $$;

create or replace function public.staff_save_class_attendance(
  p_class_id uuid,p_date date,p_student_id uuid,p_status public.attendance_status,p_late_minutes integer default null,p_absence_reason text default null,p_note text default null
) returns void language plpgsql security definer set search_path=public as $$
declare lesson_id uuid;
begin
  lesson_id:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  if not exists(select 1 from public.enrollments where class_id=p_class_id and student_id=p_student_id and status='active') then raise exception '이 클래스의 수강생이 아닙니다.'; end if;
  if p_status='late' and coalesce(p_late_minutes,0)<1 then raise exception '지각 시간을 입력해 주세요.'; end if;
  if p_status='absent' and nullif(trim(p_absence_reason),'') is null then raise exception '결석 사유를 입력해 주세요.'; end if;
  insert into public.attendance(lesson_id,student_id,status,checked_at,note,makeup_required,late_minutes,absence_reason)
  values(lesson_id,p_student_id,p_status,now(),nullif(trim(p_note),''),p_status='absent',case when p_status='late' then p_late_minutes end,case when p_status='absent' then nullif(trim(p_absence_reason),'') end)
  on conflict(lesson_id,student_id) do update set status=excluded.status,checked_at=now(),note=excluded.note,makeup_required=excluded.makeup_required,late_minutes=excluded.late_minutes,absence_reason=excluded.absence_reason;
end $$;

revoke all on function public.staff_create_subject(text,text),public.teacher_class_workspace(),public.staff_class_day(uuid,date),public.staff_save_class_day(uuid,date,text,text,text),public.staff_save_class_attendance(uuid,date,uuid,public.attendance_status,integer,text,text) from public;
grant execute on function public.staff_create_subject(text,text),public.teacher_class_workspace(),public.staff_class_day(uuid,date),public.staff_save_class_day(uuid,date,text,text,text),public.staff_save_class_attendance(uuid,date,uuid,public.attendance_status,integer,text,text) to authenticated;
