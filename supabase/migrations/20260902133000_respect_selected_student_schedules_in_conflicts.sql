-- 학생별로 실제 선택한 정규수업 시간만 충돌 검사에 사용합니다.

create or replace function public.student_uses_class_schedule(p_student_id uuid,p_schedule_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select case
    when exists(select 1 from public.student_schedule_assignments where student_id=p_student_id)
      then exists(select 1 from public.student_schedule_assignments where student_id=p_student_id and class_schedule_id=p_schedule_id)
    else true
  end
$$;

create or replace function public.assert_student_schedule_selection_available(p_student_id uuid,p_schedule_ids uuid[])
returns void language plpgsql security definer set search_path=public as $$
declare requested uuid[]:=coalesce(p_schedule_ids,'{}'::uuid[]); conflict_text text;
begin
  select c1.name||' '||to_char(cs1.start_time,'HH24:MI')||'–'||to_char(cs1.end_time,'HH24:MI')||
    ' / '||c2.name||' '||to_char(cs2.start_time,'HH24:MI')||'–'||to_char(cs2.end_time,'HH24:MI')
  into conflict_text
  from unnest(requested) a(id)
  join public.class_schedules cs1 on cs1.id=a.id
  join public.classes c1 on c1.id=cs1.class_id
  join unnest(requested) b(id) on b.id>a.id
  join public.class_schedules cs2 on cs2.id=b.id
  join public.classes c2 on c2.id=cs2.class_id
  where cs1.weekday=cs2.weekday
    and cs1.start_time<cs2.end_time and cs1.end_time>cs2.start_time
    and daterange(coalesce(cs1.valid_from,'-infinity'::date),coalesce(cs1.valid_until,'infinity'::date),'[]')
      && daterange(coalesce(cs2.valid_from,'-infinity'::date),coalesce(cs2.valid_until,'infinity'::date),'[]')
  order by cs1.weekday,cs1.start_time limit 1;
  if conflict_text is not null then
    raise exception '학생 시간 충돌: % 수업 시간이 겹칩니다.',conflict_text;
  end if;

  select c.name||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI')||
    ' / '||coalesce(a.subject,'첨삭')||' 첨삭 '||
    to_char(public.correction_time_start(a.start_time,a.slot_index),'HH24:MI')||'–'||
    to_char(public.correction_time_end(a.end_time,a.slot_index),'HH24:MI')
  into conflict_text
  from unnest(requested) r(id)
  join public.class_schedules cs on cs.id=r.id
  join public.classes c on c.id=cs.class_id
  join public.correction_assignments a on a.student_id=p_student_id and a.active and a.weekday=cs.weekday
  where public.correction_time_start(a.start_time,a.slot_index)<cs.end_time
    and public.correction_time_end(a.end_time,a.slot_index)>cs.start_time
    and daterange(coalesce(cs.valid_from,'-infinity'::date),coalesce(cs.valid_until,'infinity'::date),'[]')
      && daterange(a.valid_from,coalesce(a.valid_until,'infinity'::date),'[]')
  order by cs.weekday,cs.start_time limit 1;
  if conflict_text is not null then
    raise exception '학생 시간 충돌: % 시간이 겹칩니다.',conflict_text;
  end if;

  select c.name||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI')||
    ' / 첨삭 일정변경 '||to_char(x.target_date,'YYYY-MM-DD')||' '||
    to_char(x.target_start_time,'HH24:MI')||'–'||to_char(x.target_end_time,'HH24:MI')
  into conflict_text
  from unnest(requested) r(id)
  join public.class_schedules cs on cs.id=r.id
  join public.classes c on c.id=cs.class_id
  join public.correction_assignments a on a.student_id=p_student_id
  join public.correction_schedule_exceptions x on x.assignment_id=a.id and x.kind in ('move','extra')
  where x.target_date>=current_date and extract(isodow from x.target_date)::smallint=cs.weekday
    and (cs.valid_from is null or cs.valid_from<=x.target_date)
    and (cs.valid_until is null or cs.valid_until>=x.target_date)
    and x.target_start_time<cs.end_time and x.target_end_time>cs.start_time
  order by x.target_date,cs.start_time limit 1;
  if conflict_text is not null then
    raise exception '학생 시간 충돌: % 시간이 겹칩니다.',conflict_text;
  end if;
end $$;

create or replace function public.staff_save_class_student_schedule_assignments(p_class_id uuid,p_student_id uuid,p_schedule_ids uuid[])
returns void language plpgsql security definer set search_path=public as $$
declare requested uuid[]:=coalesce(p_schedule_ids,'{}'::uuid[]); prospective uuid[];
begin
  if not public.is_staff() then raise exception '교직원만 수강 요일을 저장할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then
    raise exception '담당 클래스의 수강 요일만 설정할 수 있습니다.';
  end if;
  if not exists(select 1 from public.enrollments where class_id=p_class_id and student_id=p_student_id and status='active') then
    raise exception '현재 이 클래스를 수강 중인 학생이 아닙니다.';
  end if;
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
    select cs.id
    from public.enrollments e join public.classes c on c.id=e.class_id and c.active
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
    where e.student_id=p_student_id and e.status='active'
      and (cs.valid_from is null or cs.valid_from<=current_date) and (cs.valid_until is null or cs.valid_until>=current_date)
    on conflict do nothing;
  end if;
  delete from public.student_schedule_assignments ssa using public.class_schedules cs
  where ssa.class_schedule_id=cs.id and ssa.student_id=p_student_id and cs.class_id=p_class_id;
  insert into public.student_schedule_assignments(student_id,class_schedule_id,assigned_by)
  select p_student_id,id,auth.uid() from unnest(requested) id on conflict do nothing;
end $$;

create or replace function public.staff_save_student_schedule_assignments(p_student_id uuid,p_schedule_ids uuid[])
returns void language plpgsql security definer set search_path=public as $$
declare requested uuid[]:=coalesce(p_schedule_ids,'{}'::uuid[]);
begin
  if not public.can_manage_student_schedule(p_student_id) then raise exception '관리자 또는 담당 선생님만 교차수강을 배정할 수 있습니다.'; end if;
  if cardinality(requested)<>(select count(distinct id) from unnest(requested) id) then raise exception '중복된 수업 시간이 포함되어 있습니다.'; end if;
  if exists(select 1 from unnest(requested) requested_id where not exists(
    select 1 from public.class_schedules cs join public.enrollments e on e.class_id=cs.class_id
    where cs.id=requested_id and e.student_id=p_student_id and e.status='active'
  )) then raise exception '현재 수강 중인 클래스의 시간만 배정할 수 있습니다.'; end if;
  perform pg_advisory_xact_lock(hashtextextended('student_schedule:'||p_student_id::text,0));
  perform public.assert_student_schedule_selection_available(p_student_id,requested);
  delete from public.student_schedule_assignments where student_id=p_student_id;
  insert into public.student_schedule_assignments(student_id,class_schedule_id,assigned_by)
  select p_student_id,id,auth.uid() from unnest(requested) id on conflict do nothing;
end $$;

create or replace function public.assert_class_student_schedule_available(p_schedule_id uuid,p_class_id uuid,p_weekday smallint,p_start_time time,p_end_time time)
returns void language plpgsql security definer set search_path=public as $$
declare conflict_text text;
begin
  select s.name||' · '||c.name||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI') into conflict_text
  from public.enrollments mine join public.students s on s.id=mine.student_id
  join public.enrollments other on other.student_id=mine.student_id and other.status='active' and other.class_id<>p_class_id
  join public.class_schedules cs on cs.class_id=other.class_id and cs.weekday=p_weekday join public.classes c on c.id=other.class_id and c.active
  where mine.class_id=p_class_id and mine.status='active'
    and public.student_uses_class_schedule(mine.student_id,p_schedule_id)
    and public.student_uses_class_schedule(mine.student_id,cs.id)
    and cs.start_time<p_end_time and cs.end_time>p_start_time and cs.id<>p_schedule_id
  order by s.name,cs.start_time limit 1;
  if conflict_text is not null then raise exception '학생 시간 충돌: % 수업과 겹칩니다.',conflict_text; end if;

  select s.name||' · '||coalesce(a.subject,'첨삭')||' 첨삭 '||to_char(public.correction_time_start(a.start_time,a.slot_index),'HH24:MI')||'–'||to_char(public.correction_time_end(a.end_time,a.slot_index),'HH24:MI') into conflict_text
  from public.enrollments e join public.students s on s.id=e.student_id
  join public.correction_assignments a on a.student_id=e.student_id and a.active and a.weekday=p_weekday
  where e.class_id=p_class_id and e.status='active' and public.student_uses_class_schedule(e.student_id,p_schedule_id)
    and public.correction_time_start(a.start_time,a.slot_index)<p_end_time and public.correction_time_end(a.end_time,a.slot_index)>p_start_time
  order by s.name,public.correction_time_start(a.start_time,a.slot_index) limit 1;
  if conflict_text is not null then raise exception '학생 시간 충돌: % 고정시간과 겹칩니다.',conflict_text; end if;

  select s.name||' · '||coalesce(a.subject,'첨삭')||' 첨삭 일정변경 '||to_char(x.target_date,'YYYY-MM-DD')||' '||
    to_char(x.target_start_time,'HH24:MI')||'–'||to_char(x.target_end_time,'HH24:MI') into conflict_text
  from public.enrollments e join public.students s on s.id=e.student_id
  join public.correction_assignments a on a.student_id=e.student_id
  join public.correction_schedule_exceptions x on x.assignment_id=a.id and x.kind in ('move','extra')
  where e.class_id=p_class_id and e.status='active' and public.student_uses_class_schedule(e.student_id,p_schedule_id)
    and x.target_date>=current_date and extract(isodow from x.target_date)::smallint=p_weekday
    and x.target_start_time<p_end_time and x.target_end_time>p_start_time
  order by x.target_date,s.name limit 1;
  if conflict_text is not null then raise exception '학생 시간 충돌: % 시간과 겹칩니다.',conflict_text; end if;
end $$;

create or replace function public.prevent_correction_conflict()
returns trigger language plpgsql security definer set search_path=public as $$
declare conflict_text text; ns time; ne time;
begin
  if not coalesce(new.active,true) then return new; end if;
  ns:=public.correction_time_start(new.start_time,new.slot_index); ne:=public.correction_time_end(new.end_time,new.slot_index);
  select c.name||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI') into conflict_text
  from public.enrollments e join public.class_schedules cs on cs.class_id=e.class_id and cs.weekday=new.weekday join public.classes c on c.id=e.class_id and c.active
  where e.student_id=new.student_id and e.status='active' and public.student_uses_class_schedule(new.student_id,cs.id)
    and cs.start_time<ne and cs.end_time>ns order by cs.start_time limit 1;
  if conflict_text is not null then raise exception '학생 시간 충돌: % 수업과 겹칩니다.',conflict_text; end if;
  select coalesce(a.subject,'첨삭')||' 첨삭 '||to_char(public.correction_time_start(a.start_time,a.slot_index),'HH24:MI')||'–'||to_char(public.correction_time_end(a.end_time,a.slot_index),'HH24:MI') into conflict_text
  from public.correction_assignments a where a.id<>new.id and a.student_id=new.student_id and a.active and a.weekday=new.weekday
    and daterange(a.valid_from,coalesce(a.valid_until,'infinity'::date),'[]')&&daterange(new.valid_from,coalesce(new.valid_until,'infinity'::date),'[]')
    and public.correction_time_start(a.start_time,a.slot_index)<ne and public.correction_time_end(a.end_time,a.slot_index)>ns limit 1;
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
  from public.enrollments e join public.class_schedules cs on cs.class_id=e.class_id and cs.weekday=target_day join public.classes c on c.id=e.class_id and c.active
  where e.student_id=sid and e.status='active' and public.student_uses_class_schedule(sid,cs.id)
    and (cs.valid_from is null or cs.valid_from<=new.target_date) and (cs.valid_until is null or cs.valid_until>=new.target_date)
    and cs.start_time<new.target_end_time and cs.end_time>new.target_start_time order by cs.start_time limit 1;
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

create or replace function public.prevent_legacy_correction_exception_student_conflict()
returns trigger language plpgsql security definer set search_path=public as $$
declare sid uuid; ts time; te time; conflict_text text;
begin
  select student_id into sid from public.correction_assignments where id=new.assignment_id;
  ts:=public.correction_time_start(null,new.slot_index); te:=public.correction_time_end(null,new.slot_index);
  select c.name||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI') into conflict_text
  from public.enrollments e join public.class_schedules cs on cs.class_id=e.class_id and cs.weekday=new.weekday join public.classes c on c.id=e.class_id and c.active
  where e.student_id=sid and e.status='active' and public.student_uses_class_schedule(sid,cs.id)
    and cs.start_time<te and cs.end_time>ts order by cs.start_time limit 1;
  if conflict_text is not null then raise exception '학생 시간 충돌: % 수업과 겹칩니다.',conflict_text; end if;
  return new;
end $$;

revoke all on function public.student_uses_class_schedule(uuid,uuid),public.assert_student_schedule_selection_available(uuid,uuid[]) from public,anon,authenticated;
revoke all on function public.assert_class_student_schedule_available(uuid,uuid,smallint,time,time) from public,anon,authenticated;
revoke all on function public.prevent_correction_conflict(),public.prevent_correction_schedule_exception_conflict(),public.prevent_legacy_correction_exception_student_conflict() from public,anon,authenticated;
revoke all on function public.staff_save_class_student_schedule_assignments(uuid,uuid,uuid[]),public.staff_save_student_schedule_assignments(uuid,uuid[]) from public,anon;
grant execute on function public.staff_save_class_student_schedule_assignments(uuid,uuid,uuid[]),public.staff_save_student_schedule_assignments(uuid,uuid[]) to authenticated;
notify pgrst,'reload schema';
