-- 학생의 정규수업, 고정 첨삭, 일정 변경 첨삭이 겹치지 않도록 저장 단계에서 검사합니다.

create or replace function public.correction_time_start(p_start time, p_slot smallint)
returns time language sql immutable set search_path=public as $$
  select coalesce(p_start,case p_slot when 0 then time '17:30' when 1 then time '19:00' when 2 then time '20:30' end)
$$;

create or replace function public.correction_time_end(p_end time, p_slot smallint)
returns time language sql immutable set search_path=public as $$
  select coalesce(p_end,case p_slot when 0 then time '19:00' when 1 then time '20:30' when 2 then time '22:00' end)
$$;

create or replace function public.assert_class_student_schedule_available(
  p_schedule_id uuid,p_class_id uuid,p_weekday smallint,p_start_time time,p_end_time time
) returns void language plpgsql security definer set search_path=public as $$
declare conflict_text text;
begin
  select s.name||' · '||c.name||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI')
  into conflict_text
  from public.enrollments mine
  join public.students s on s.id=mine.student_id
  join public.enrollments other on other.student_id=mine.student_id and other.status='active' and other.class_id<>p_class_id
  join public.class_schedules cs on cs.class_id=other.class_id and cs.weekday=p_weekday
  join public.classes c on c.id=other.class_id and c.active
  where mine.class_id=p_class_id and mine.status='active'
    and cs.start_time<p_end_time and cs.end_time>p_start_time
    and cs.id<>coalesce(p_schedule_id,'00000000-0000-0000-0000-000000000000'::uuid)
  order by s.name,cs.start_time limit 1;
  if conflict_text is not null then
    raise exception '학생 시간 충돌: % 수업과 겹칩니다.',conflict_text;
  end if;

  select s.name||' · '||coalesce(a.subject,'첨삭')||' 첨삭 '||
    to_char(public.correction_time_start(a.start_time,a.slot_index),'HH24:MI')||'–'||
    to_char(public.correction_time_end(a.end_time,a.slot_index),'HH24:MI')
  into conflict_text
  from public.enrollments e join public.students s on s.id=e.student_id
  join public.correction_assignments a on a.student_id=e.student_id and a.active and a.weekday=p_weekday
  where e.class_id=p_class_id and e.status='active'
    and public.correction_time_start(a.start_time,a.slot_index)<p_end_time
    and public.correction_time_end(a.end_time,a.slot_index)>p_start_time
  order by s.name,public.correction_time_start(a.start_time,a.slot_index) limit 1;
  if conflict_text is not null then
    raise exception '학생 시간 충돌: % 고정시간과 겹칩니다.',conflict_text;
  end if;

  select s.name||' · '||coalesce(a.subject,'첨삭')||' 첨삭 일정변경 '||to_char(x.target_date,'YYYY-MM-DD')||' '||
    to_char(x.target_start_time,'HH24:MI')||'–'||to_char(x.target_end_time,'HH24:MI')
  into conflict_text
  from public.enrollments e join public.students s on s.id=e.student_id
  join public.correction_assignments a on a.student_id=e.student_id
  join public.correction_schedule_exceptions x on x.assignment_id=a.id and x.kind in ('move','extra')
  where e.class_id=p_class_id and e.status='active' and x.target_date>=current_date
    and extract(isodow from x.target_date)::smallint=p_weekday
    and x.target_start_time<p_end_time and x.target_end_time>p_start_time
  order by x.target_date,s.name limit 1;
  if conflict_text is not null then
    raise exception '학생 시간 충돌: % 시간과 겹칩니다.',conflict_text;
  end if;
end $$;

create or replace function public.prevent_class_schedule_conflict()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_table_name='class_schedules' then
    perform public.assert_class_student_schedule_available(new.id,new.class_id,new.weekday,new.start_time,new.end_time);
    if exists(select 1 from public.class_teachers mine join public.class_teachers theirs on theirs.profile_id=mine.profile_id and theirs.class_id<>new.class_id join public.class_schedules cs on cs.class_id=theirs.class_id where mine.class_id=new.class_id and cs.weekday=new.weekday and cs.start_time<new.end_time and cs.end_time>new.start_time and cs.id<>new.id) then
      raise exception '선택한 선생님에게 같은 시간의 다른 수업이 있습니다.';
    end if;
    if exists(select 1 from public.class_schedules cs join public.classes mine on mine.id=new.class_id join public.classes other on other.id=cs.class_id where cs.id<>new.id and cs.weekday=new.weekday and cs.start_time<new.end_time and cs.end_time>new.start_time and nullif(trim(mine.room),'') is not null and mine.room=other.room) then
      raise exception '같은 강의실에 겹치는 수업이 있습니다.';
    end if;
  else
    if exists(select 1 from public.class_schedules mine join public.class_teachers ct on ct.profile_id=new.profile_id and ct.class_id<>new.class_id join public.class_schedules other on other.class_id=ct.class_id where mine.class_id=new.class_id and mine.weekday=other.weekday and mine.start_time<other.end_time and mine.end_time>other.start_time) then
      raise exception '선택한 선생님에게 같은 시간의 다른 수업이 있습니다.';
    end if;
  end if;
  return new;
end $$;

create or replace function public.prevent_correction_conflict()
returns trigger language plpgsql security definer set search_path=public as $$
declare conflict_text text; ns time; ne time;
begin
  if not coalesce(new.active,true) then return new; end if;
  ns:=public.correction_time_start(new.start_time,new.slot_index);
  ne:=public.correction_time_end(new.end_time,new.slot_index);

  select c.name||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI') into conflict_text
  from public.enrollments e join public.class_schedules cs on cs.class_id=e.class_id and cs.weekday=new.weekday
  join public.classes c on c.id=e.class_id and c.active
  where e.student_id=new.student_id and e.status='active' and cs.start_time<ne and cs.end_time>ns
  order by cs.start_time limit 1;
  if conflict_text is not null then raise exception '학생 시간 충돌: % 수업과 겹칩니다.',conflict_text; end if;

  select coalesce(a.subject,'첨삭')||' 첨삭 '||to_char(public.correction_time_start(a.start_time,a.slot_index),'HH24:MI')||'–'||to_char(public.correction_time_end(a.end_time,a.slot_index),'HH24:MI') into conflict_text
  from public.correction_assignments a
  where a.id<>new.id and a.student_id=new.student_id and a.active and a.weekday=new.weekday
    and daterange(a.valid_from,coalesce(a.valid_until,'infinity'::date),'[]') && daterange(new.valid_from,coalesce(new.valid_until,'infinity'::date),'[]')
    and public.correction_time_start(a.start_time,a.slot_index)<ne and public.correction_time_end(a.end_time,a.slot_index)>ns
  order by public.correction_time_start(a.start_time,a.slot_index) limit 1;
  if conflict_text is not null then raise exception '학생 시간 충돌: % 고정시간과 겹칩니다.',conflict_text; end if;

  select coalesce(a.subject,'첨삭')||' 첨삭 일정변경 '||to_char(x.target_date,'YYYY-MM-DD')||' '||to_char(x.target_start_time,'HH24:MI')||'–'||to_char(x.target_end_time,'HH24:MI') into conflict_text
  from public.correction_schedule_exceptions x join public.correction_assignments a on a.id=x.assignment_id
  where a.student_id=new.student_id and x.kind in ('move','extra') and x.target_date>=current_date
    and extract(isodow from x.target_date)::smallint=new.weekday
    and x.target_start_time<ne and x.target_end_time>ns
  order by x.target_date,x.target_start_time limit 1;
  if conflict_text is not null then raise exception '학생 시간 충돌: % 시간과 겹칩니다.',conflict_text; end if;
  return new;
end $$;

create or replace function public.prevent_correction_schedule_exception_conflict()
returns trigger language plpgsql security definer set search_path=public as $$
declare sid uuid; conflict_text text; target_day smallint;
begin
  if new.kind='cancel' then return new; end if;
  select student_id into sid from public.correction_assignments where id=new.assignment_id;
  target_day:=extract(isodow from new.target_date)::smallint;

  select c.name||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI') into conflict_text
  from public.enrollments e join public.class_schedules cs on cs.class_id=e.class_id and cs.weekday=target_day
  join public.classes c on c.id=e.class_id and c.active
  where e.student_id=sid and e.status='active'
    and (cs.valid_from is null or cs.valid_from<=new.target_date) and (cs.valid_until is null or cs.valid_until>=new.target_date)
    and cs.start_time<new.target_end_time and cs.end_time>new.target_start_time
  order by cs.start_time limit 1;
  if conflict_text is not null then raise exception '학생 시간 충돌: % 수업과 겹칩니다.',conflict_text; end if;

  select coalesce(a.subject,'첨삭')||' 첨삭 '||to_char(public.correction_time_start(a.start_time,a.slot_index),'HH24:MI')||'–'||to_char(public.correction_time_end(a.end_time,a.slot_index),'HH24:MI') into conflict_text
  from public.correction_assignments a
  where a.id<>new.assignment_id and a.student_id=sid and a.active and a.weekday=target_day
    and a.valid_from<=new.target_date and (a.valid_until is null or a.valid_until>=new.target_date)
    and public.correction_time_start(a.start_time,a.slot_index)<new.target_end_time
    and public.correction_time_end(a.end_time,a.slot_index)>new.target_start_time
    and not exists(select 1 from public.correction_schedule_exceptions moved where moved.assignment_id=a.id and moved.original_date=new.target_date and moved.kind in ('move','cancel'))
  order by public.correction_time_start(a.start_time,a.slot_index) limit 1;
  if conflict_text is not null then raise exception '학생 시간 충돌: % 고정시간과 겹칩니다.',conflict_text; end if;

  select coalesce(a.subject,'첨삭')||' 첨삭 일정변경 '||to_char(x.target_start_time,'HH24:MI')||'–'||to_char(x.target_end_time,'HH24:MI') into conflict_text
  from public.correction_schedule_exceptions x join public.correction_assignments a on a.id=x.assignment_id
  where x.id<>new.id and a.student_id=sid and x.kind in ('move','extra') and x.target_date=new.target_date
    and x.target_start_time<new.target_end_time and x.target_end_time>new.target_start_time
  order by x.target_start_time limit 1;
  if conflict_text is not null then raise exception '학생 시간 충돌: % 시간과 겹칩니다.',conflict_text; end if;
  return new;
end $$;

drop trigger if exists correction_schedule_exceptions_prevent_student_conflict on public.correction_schedule_exceptions;
create trigger correction_schedule_exceptions_prevent_student_conflict before insert or update on public.correction_schedule_exceptions
for each row execute function public.prevent_correction_schedule_exception_conflict();

-- 구형 선생님 시간표의 "이번 주만" 변경도 같은 학생 충돌 검사를 적용합니다.
create or replace function public.prevent_legacy_correction_exception_student_conflict()
returns trigger language plpgsql security definer set search_path=public as $$
declare sid uuid; d date; ts time; te time; conflict_text text;
begin
  select student_id into sid from public.correction_assignments where id=new.assignment_id;
  d:=new.week_start+(new.weekday-1); ts:=public.correction_time_start(null,new.slot_index); te:=public.correction_time_end(null,new.slot_index);
  select c.name||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI') into conflict_text
  from public.enrollments e join public.class_schedules cs on cs.class_id=e.class_id and cs.weekday=new.weekday join public.classes c on c.id=e.class_id and c.active
  where e.student_id=sid and e.status='active' and cs.start_time<te and cs.end_time>ts order by cs.start_time limit 1;
  if conflict_text is not null then raise exception '학생 시간 충돌: % 수업과 겹칩니다.',conflict_text; end if;
  return new;
end $$;

drop trigger if exists correction_exceptions_prevent_student_conflict on public.correction_exceptions;
create trigger correction_exceptions_prevent_student_conflict before insert or update on public.correction_exceptions
for each row execute function public.prevent_legacy_correction_exception_student_conflict();

notify pgrst,'reload schema';
