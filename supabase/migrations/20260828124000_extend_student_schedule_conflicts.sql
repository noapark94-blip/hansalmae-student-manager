-- 보강·추가수업과 클래스 수강 추가에도 학생 시간 충돌 검사를 적용합니다.

create or replace function public.student_date_conflict_message(
  p_student_id uuid,p_date date,p_start_time time,p_end_time time,
  p_exclude_special_id uuid default null,p_exclude_makeup_id uuid default null,p_exclude_source_makeup_id uuid default null
) returns text language plpgsql security definer set search_path=public as $$
declare message text; day_no smallint:=extract(isodow from p_date)::smallint;
begin
  select c.name||' 정규수업 '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI') into message
  from public.enrollments e join public.class_schedules cs on cs.class_id=e.class_id and cs.weekday=day_no
  join public.classes c on c.id=e.class_id and c.active
  where e.student_id=p_student_id and e.status='active'
    and (cs.valid_from is null or cs.valid_from<=p_date) and (cs.valid_until is null or cs.valid_until>=p_date)
    and cs.start_time<p_end_time and cs.end_time>p_start_time
    and not exists(select 1 from public.schedule_exceptions x where x.class_id=cs.class_id and x.original_date=p_date and x.kind='cancelled')
  order by cs.start_time limit 1;
  if message is not null then return message; end if;

  select coalesce(a.subject,'첨삭')||' 첨삭 '||to_char(public.correction_time_start(a.start_time,a.slot_index),'HH24:MI')||'–'||to_char(public.correction_time_end(a.end_time,a.slot_index),'HH24:MI') into message
  from public.correction_assignments a
  where a.student_id=p_student_id and a.active and a.weekday=day_no and a.valid_from<=p_date and (a.valid_until is null or a.valid_until>=p_date)
    and public.correction_time_start(a.start_time,a.slot_index)<p_end_time and public.correction_time_end(a.end_time,a.slot_index)>p_start_time
    and not exists(select 1 from public.correction_schedule_exceptions x where x.assignment_id=a.id and x.original_date=p_date and x.kind in ('move','cancel'))
  order by public.correction_time_start(a.start_time,a.slot_index) limit 1;
  if message is not null then return message; end if;

  select coalesce(a.subject,'첨삭')||' 첨삭 일정변경 '||to_char(x.target_start_time,'HH24:MI')||'–'||to_char(x.target_end_time,'HH24:MI') into message
  from public.correction_schedule_exceptions x join public.correction_assignments a on a.id=x.assignment_id
  where a.student_id=p_student_id and x.kind in ('move','extra') and x.target_date=p_date
    and x.target_start_time<p_end_time and x.target_end_time>p_start_time
  order by x.target_start_time limit 1;
  if message is not null then return message; end if;

  select case when l.kind='makeup' then '개별 보강 ' else '추가수업 ' end||to_char(l.starts_at,'HH24:MI')||'–'||to_char(l.ends_at,'HH24:MI') into message
  from public.teacher_special_lesson_students ss join public.teacher_special_lessons l on l.id=ss.session_id
  where ss.student_id=p_student_id and l.id<>coalesce(p_exclude_special_id,'00000000-0000-0000-0000-000000000000'::uuid)
    and l.lesson_date=p_date and l.starts_at<p_end_time and l.ends_at>p_start_time
  order by l.starts_at limit 1;
  if message is not null then return message; end if;

  select '결석 보강 '||to_char(ms.scheduled_at at time zone 'Asia/Seoul','HH24:MI')||'–'||to_char(ms.ends_at at time zone 'Asia/Seoul','HH24:MI') into message
  from public.makeup_sessions ms join public.attendance at on at.id=ms.attendance_id
  where at.student_id=p_student_id and ms.status='scheduled'
    and ms.id<>coalesce(p_exclude_makeup_id,'00000000-0000-0000-0000-000000000000'::uuid)
    and (ms.scheduled_at at time zone 'Asia/Seoul')::date=p_date
    and (ms.scheduled_at at time zone 'Asia/Seoul')::time<p_end_time and (ms.ends_at at time zone 'Asia/Seoul')::time>p_start_time
  order by ms.scheduled_at limit 1;
  if message is not null then return message; end if;

  select '결석 보강 '||to_char(sm.scheduled_at at time zone 'Asia/Seoul','HH24:MI')||'–'||to_char(sm.ends_at at time zone 'Asia/Seoul','HH24:MI') into message
  from public.source_makeup_sessions sm
  where sm.student_id=p_student_id and sm.status='scheduled'
    and sm.id<>coalesce(p_exclude_source_makeup_id,'00000000-0000-0000-0000-000000000000'::uuid)
    and (sm.scheduled_at at time zone 'Asia/Seoul')::date=p_date
    and (sm.scheduled_at at time zone 'Asia/Seoul')::time<p_end_time and (sm.ends_at at time zone 'Asia/Seoul')::time>p_start_time
  order by sm.scheduled_at limit 1;
  return message;
end $$;

create or replace function public.prevent_special_lesson_student_conflict()
returns trigger language plpgsql security definer set search_path=public as $$
declare l public.teacher_special_lessons; student_name text; conflict text;
begin
  select * into l from public.teacher_special_lessons where id=new.session_id;
  select name into student_name from public.students where id=new.student_id;
  conflict:=public.student_date_conflict_message(new.student_id,l.lesson_date,l.starts_at,l.ends_at,l.id,null,null);
  if conflict is not null then raise exception '학생 시간 충돌: % · %와 겹칩니다.',student_name,conflict; end if;
  return new;
end $$;

drop trigger if exists special_lesson_students_prevent_schedule_conflict on public.teacher_special_lesson_students;
create trigger special_lesson_students_prevent_schedule_conflict before insert or update on public.teacher_special_lesson_students
for each row execute function public.prevent_special_lesson_student_conflict();

create or replace function public.prevent_special_lesson_time_conflict()
returns trigger language plpgsql security definer set search_path=public as $$
declare row_item record; conflict text;
begin
  if new.lesson_date is not distinct from old.lesson_date and new.starts_at is not distinct from old.starts_at and new.ends_at is not distinct from old.ends_at then return new; end if;
  for row_item in select ss.student_id,s.name from public.teacher_special_lesson_students ss join public.students s on s.id=ss.student_id where ss.session_id=new.id loop
    conflict:=public.student_date_conflict_message(row_item.student_id,new.lesson_date,new.starts_at,new.ends_at,new.id,null,null);
    if conflict is not null then raise exception '학생 시간 충돌: % · %와 겹칩니다.',row_item.name,conflict; end if;
  end loop;
  return new;
end $$;

drop trigger if exists special_lessons_prevent_student_time_conflict on public.teacher_special_lessons;
create trigger special_lessons_prevent_student_time_conflict before update on public.teacher_special_lessons
for each row execute function public.prevent_special_lesson_time_conflict();

create or replace function public.prevent_makeup_student_conflict()
returns trigger language plpgsql security definer set search_path=public as $$
declare sid uuid; student_name text; conflict text; local_start timestamp; local_end timestamp;
begin
  select at.student_id,s.name into sid,student_name from public.attendance at join public.students s on s.id=at.student_id where at.id=new.attendance_id;
  local_start:=new.scheduled_at at time zone 'Asia/Seoul'; local_end:=new.ends_at at time zone 'Asia/Seoul';
  conflict:=public.student_date_conflict_message(sid,local_start::date,local_start::time,local_end::time,null,new.id,null);
  if conflict is not null then raise exception '학생 시간 충돌: % · %와 겹칩니다.',student_name,conflict; end if;
  return new;
end $$;

drop trigger if exists makeup_sessions_prevent_student_conflict on public.makeup_sessions;
create trigger makeup_sessions_prevent_student_conflict before insert or update on public.makeup_sessions
for each row when (new.status='scheduled') execute function public.prevent_makeup_student_conflict();

create or replace function public.prevent_source_makeup_student_conflict()
returns trigger language plpgsql security definer set search_path=public as $$
declare student_name text; conflict text; local_start timestamp; local_end timestamp;
begin
  select name into student_name from public.students where id=new.student_id;
  local_start:=new.scheduled_at at time zone 'Asia/Seoul'; local_end:=new.ends_at at time zone 'Asia/Seoul';
  conflict:=public.student_date_conflict_message(new.student_id,local_start::date,local_start::time,local_end::time,null,null,new.id);
  if conflict is not null then raise exception '학생 시간 충돌: % · %와 겹칩니다.',student_name,conflict; end if;
  return new;
end $$;

drop trigger if exists source_makeup_sessions_prevent_student_conflict on public.source_makeup_sessions;
create trigger source_makeup_sessions_prevent_student_conflict before insert or update on public.source_makeup_sessions
for each row when (new.status='scheduled') execute function public.prevent_source_makeup_student_conflict();

create or replace function public.prevent_enrollment_student_schedule_conflict()
returns trigger language plpgsql security definer set search_path=public as $$
declare student_name text; conflict text;
begin
  if new.status<>'active' then return new; end if;
  select s.name into student_name from public.students s where s.id=new.student_id;

  select c.name||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI') into conflict
  from public.class_schedules mine join public.enrollments e on e.student_id=new.student_id and e.status='active' and e.class_id<>new.class_id
  join public.class_schedules cs on cs.class_id=e.class_id and cs.weekday=mine.weekday join public.classes c on c.id=e.class_id and c.active
  where mine.class_id=new.class_id and mine.start_time<cs.end_time and mine.end_time>cs.start_time order by mine.weekday,mine.start_time limit 1;
  if conflict is not null then raise exception '학생 시간 충돌: % · 기존 % 수업과 겹쳐 클래스를 추가할 수 없습니다.',student_name,conflict; end if;

  select coalesce(a.subject,'첨삭')||' 첨삭 '||to_char(public.correction_time_start(a.start_time,a.slot_index),'HH24:MI')||'–'||to_char(public.correction_time_end(a.end_time,a.slot_index),'HH24:MI') into conflict
  from public.class_schedules mine join public.correction_assignments a on a.student_id=new.student_id and a.active and a.weekday=mine.weekday
  where mine.class_id=new.class_id and mine.start_time<public.correction_time_end(a.end_time,a.slot_index) and mine.end_time>public.correction_time_start(a.start_time,a.slot_index)
  order by mine.weekday,mine.start_time limit 1;
  if conflict is not null then raise exception '학생 시간 충돌: % · % 고정시간과 겹쳐 클래스를 추가할 수 없습니다.',student_name,conflict; end if;
  return new;
end $$;

drop trigger if exists enrollments_prevent_student_schedule_conflict on public.enrollments;
create trigger enrollments_prevent_student_schedule_conflict before insert or update of status,class_id on public.enrollments
for each row execute function public.prevent_enrollment_student_schedule_conflict();

revoke all on function public.student_date_conflict_message(uuid,date,time,time,uuid,uuid,uuid) from public,anon,authenticated;
revoke all on function public.prevent_special_lesson_student_conflict() from public,anon,authenticated;
revoke all on function public.prevent_special_lesson_time_conflict() from public,anon,authenticated;
revoke all on function public.prevent_makeup_student_conflict() from public,anon,authenticated;
revoke all on function public.prevent_source_makeup_student_conflict() from public,anon,authenticated;
revoke all on function public.prevent_enrollment_student_schedule_conflict() from public,anon,authenticated;

notify pgrst,'reload schema';
