CREATE OR REPLACE FUNCTION public.assert_class_student_schedule_available(p_schedule_id uuid, p_class_id uuid, p_weekday smallint, p_start_time time without time zone, p_end_time time without time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$
;
CREATE OR REPLACE FUNCTION public.correction_time_end(p_end time without time zone, p_slot smallint)
 RETURNS time without time zone
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(p_end,case p_slot when 0 then time '19:00' when 1 then time '20:30' when 2 then time '22:00' end)
$function$
;
CREATE OR REPLACE FUNCTION public.correction_time_start(p_start time without time zone, p_slot smallint)
 RETURNS time without time zone
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
  select coalesce(p_start,case p_slot when 0 then time '17:30' when 1 then time '19:00' when 2 then time '20:30' end)
$function$
;
CREATE OR REPLACE FUNCTION public.prevent_class_schedule_conflict()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$
;
CREATE OR REPLACE FUNCTION public.staff_guard_class_schedule(p_id uuid, p_class_id uuid, p_base jsonb, p_values jsonb, p_delete boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v jsonb; current_teachers jsonb; result_id uuid;
begin
 if auth.uid() is null or not coalesce(public.is_staff(),false) then raise exception '수업 배정 권한이 없습니다.'; end if;
 perform pg_advisory_xact_lock(hashtext('hansalmae_class_schedule_save'));
 perform 1 from public.classes where id=p_class_id and active for update;
 if not found then raise exception '운영 중인 클래스를 찾을 수 없습니다.'; end if;
 select coalesce(jsonb_agg(profile_id::text order by profile_id),'[]'::jsonb) into current_teachers from public.class_teachers where class_id=p_class_id;
 if p_id is not null then
   select jsonb_build_object('weekday',weekday,'startTime',to_char(start_time,'HH24:MI'),'endTime',to_char(end_time,'HH24:MI'),'teacherIds',current_teachers)
   into v from public.class_schedules where id=p_id and class_id=p_class_id for update;
   if not found then raise exception '이미 변경되거나 삭제된 수업 배정입니다. 창을 다시 열어 주세요.'; end if;
 else
   v:=jsonb_build_object('teacherIds',current_teachers);
 end if;
 if v is distinct from p_base then raise exception '다른 선생님이 수업 시간 또는 담당을 변경했습니다. 입력 내용은 유지됩니다. 최신 시간표를 확인한 뒤 다시 열어 주세요.'; end if;
 if p_delete then
   if p_id is null then raise exception '삭제할 배정이 없습니다.'; end if;
   if exists(select 1 from public.student_schedule_assignments where class_schedule_id=p_id) then raise exception '개별 수강요일이 배정된 시간입니다. 학생의 수강요일을 먼저 조정해 주세요.'; end if;
   delete from public.class_schedules where id=p_id;
   return p_id;
 end if;
 result_id:=public.staff_save_class_schedule(p_id,p_class_id,(p_values->>'weekday')::smallint,(p_values->>'startTime')::time,(p_values->>'endTime')::time,array(select jsonb_array_elements_text(p_values->'teacherIds')::uuid));
 return result_id;
end $function$
;
CREATE OR REPLACE FUNCTION public.staff_save_class_schedule(p_schedule_id uuid, p_class_id uuid, p_weekday smallint, p_start_time time without time zone, p_end_time time without time zone, p_teacher_ids uuid[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  saved_id uuid;
  teacher_id uuid;
  normalized_teacher_ids uuid[];
  target_room text;
  target_class_name text;
  teacher_conflicts text;
  room_conflict text;
begin
  if not coalesce(public.is_staff(),false) then raise exception '교직원만 수업을 배정할 수 있습니다.'; end if;
  if p_weekday not between 1 and 7 then raise exception '수업 요일을 확인해 주세요.'; end if;
  if p_start_time>=p_end_time then raise exception '종료 시간은 시작 시간보다 늦어야 합니다.'; end if;

  select coalesce(array_agg(distinct selected.teacher_id order by selected.teacher_id),'{}'::uuid[])
  into normalized_teacher_ids
  from unnest(coalesce(p_teacher_ids,'{}'::uuid[])) selected(teacher_id);

  if coalesce(array_length(normalized_teacher_ids,1),0)=0 and public.current_user_role()<>'admin' then
    raise exception '담당 선생님을 한 명 이상 선택해 주세요.';
  end if;

  select nullif(trim(room),''),name into target_room,target_class_name
  from public.classes where id=p_class_id and active;
  if target_class_name is null then raise exception '운영 중인 클래스를 찾을 수 없습니다.'; end if;

  perform pg_advisory_xact_lock(hashtext('hansalmae_class_schedule_save'));
  if exists(
    select 1 from public.class_schedules cs
    where cs.class_id=p_class_id
      and cs.weekday=p_weekday
      and cs.start_time<p_end_time
      and cs.end_time>p_start_time
      and cs.id<>coalesce(p_schedule_id,'00000000-0000-0000-0000-000000000000'::uuid)
  ) then
    raise exception '클래스 시간 충돌: %에 같은 시간대 배정이 이미 있습니다.',target_class_name;
  end if;

  select string_agg(
    distinct p.display_name||' · '||c.name||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI'),
    ' / ' order by p.display_name||' · '||c.name||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI')
  ) into teacher_conflicts
  from unnest(normalized_teacher_ids) selected_teacher(id)
  join public.profiles p on p.id=selected_teacher.id
  join public.class_teachers ct on ct.profile_id=selected_teacher.id and ct.class_id<>p_class_id
  join public.class_schedules cs on cs.class_id=ct.class_id
  join public.classes c on c.id=cs.class_id
  where cs.weekday=p_weekday
    and cs.start_time<p_end_time
    and cs.end_time>p_start_time
    and cs.id<>coalesce(p_schedule_id,'00000000-0000-0000-0000-000000000000'::uuid);
  if teacher_conflicts is not null then raise exception '교사 시간 충돌: %',teacher_conflicts; end if;

  if target_room is not null then
    select c.name||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI') into room_conflict
    from public.class_schedules cs join public.classes c on c.id=cs.class_id
    where cs.weekday=p_weekday
      and cs.start_time<p_end_time
      and cs.end_time>p_start_time
      and cs.id<>coalesce(p_schedule_id,'00000000-0000-0000-0000-000000000000'::uuid)
      and nullif(trim(c.room),'')=target_room
    order by cs.start_time limit 1;
    if room_conflict is not null then
      raise exception '교실 시간 충돌: % 강의실에 % 수업이 있습니다.',target_room,room_conflict;
    end if;
  end if;

  delete from public.class_teachers where class_id=p_class_id;
  if p_schedule_id is null then
    insert into public.class_schedules(class_id,weekday,start_time,end_time)
    values(p_class_id,p_weekday,p_start_time,p_end_time) returning id into saved_id;
  else
    update public.class_schedules set weekday=p_weekday,start_time=p_start_time,end_time=p_end_time
    where id=p_schedule_id and class_id=p_class_id returning id into saved_id;
    if saved_id is null then raise exception '수업 배정을 찾을 수 없습니다.'; end if;
  end if;
  foreach teacher_id in array normalized_teacher_ids loop
    insert into public.class_teachers(class_id,profile_id) values(p_class_id,teacher_id);
  end loop;
  return saved_id;
end
$function$
;
CREATE OR REPLACE FUNCTION public.student_uses_class_schedule(p_student_id uuid, p_schedule_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case
    when exists(select 1 from public.student_schedule_assignments where student_id=p_student_id)
      then exists(select 1 from public.student_schedule_assignments where student_id=p_student_id and class_schedule_id=p_schedule_id)
    else true
  end
$function$
;
