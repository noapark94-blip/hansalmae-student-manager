-- 관리자는 반편성을 위해 담당 선생님 없이 클래스를 먼저 만들 수 있습니다.
-- 선생님 계정은 기존처럼 본인이 담당자로 포함된 클래스만 만들고 수정할 수 있습니다.

create or replace function public.staff_save_class_schedule(
  p_schedule_id uuid,
  p_class_id uuid,
  p_weekday smallint,
  p_start_time time,
  p_end_time time,
  p_teacher_ids uuid[]
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
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
$$;

create or replace function public.staff_create_class_with_schedules(
  p_name text,
  p_subject_id uuid,
  p_room text,
  p_color text,
  p_schedules jsonb,
  p_teacher_ids uuid[]
) returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  result_id uuid;
  schedule_row jsonb;
  normalized_teacher_ids uuid[];
begin
  if not public.is_staff() then raise exception '교직원만 클래스를 만들 수 있습니다.'; end if;
  select coalesce(array_agg(distinct selected.teacher_id order by selected.teacher_id),'{}'::uuid[])
  into normalized_teacher_ids
  from unnest(coalesce(p_teacher_ids,'{}'::uuid[])) selected(teacher_id);

  if coalesce(array_length(normalized_teacher_ids,1),0)=0 and public.current_user_role()<>'admin' then
    raise exception '담당 선생님을 한 명 이상 선택해 주세요.';
  end if;
  if public.current_user_role()<>'admin' and not auth.uid()=any(normalized_teacher_ids) then
    raise exception '본인이 포함된 담당 클래스로만 만들 수 있습니다.';
  end if;
  if exists(
    select 1 from unnest(normalized_teacher_ids) selected(id)
    left join public.profiles p on p.id=selected.id and p.is_active and p.role in ('admin','teacher','manager')
    where p.id is null
  ) then raise exception '사용 가능한 담당 선생님을 선택해 주세요.'; end if;
  if coalesce(jsonb_typeof(p_schedules),'')<>'array' or jsonb_array_length(p_schedules)=0 then
    raise exception '수업 요일과 시간을 한 개 이상 입력해 주세요.';
  end if;

  result_id:=public.staff_create_my_class(p_name,p_subject_id,p_room,p_color);
  delete from public.class_teachers where class_id=result_id;
  insert into public.class_teachers(class_id,profile_id)
  select result_id,id from unnest(normalized_teacher_ids) selected(id);

  for schedule_row in select value from jsonb_array_elements(p_schedules)
  loop
    perform public.staff_save_class_schedule(
      null,
      result_id,
      (schedule_row->>'weekday')::smallint,
      (schedule_row->>'start_time')::time,
      (schedule_row->>'end_time')::time,
      normalized_teacher_ids
    );
  end loop;
  return result_id;
end
$$;

create or replace function public.staff_update_class_with_teachers(
  p_class_id uuid,
  p_name text,
  p_subject_id uuid,
  p_room text,
  p_color text,
  p_schedules jsonb,
  p_teacher_ids uuid[]
) returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  schedule_row jsonb;
  normalized_teacher_ids uuid[];
  subject_row public.academy_subjects%rowtype;
begin
  if not public.is_staff()
     or (public.current_user_role()<>'admin' and not exists(
       select 1 from public.class_teachers ct
       where ct.class_id=p_class_id and ct.profile_id=auth.uid()
     )) then raise exception '담당 클래스만 수정할 수 있습니다.'; end if;
  if nullif(trim(p_name),'') is null then raise exception '클래스 이름을 입력해 주세요.'; end if;

  select coalesce(array_agg(distinct selected.teacher_id order by selected.teacher_id),'{}'::uuid[])
  into normalized_teacher_ids
  from unnest(coalesce(p_teacher_ids,'{}'::uuid[])) selected(teacher_id);

  if coalesce(array_length(normalized_teacher_ids,1),0)=0 and public.current_user_role()<>'admin' then
    raise exception '담당 선생님을 한 명 이상 선택해 주세요.';
  end if;
  if public.current_user_role()<>'admin' and not auth.uid()=any(normalized_teacher_ids) then
    raise exception '본인을 담당 선생님에서 제외할 수 없습니다.';
  end if;
  if exists(
    select 1 from unnest(normalized_teacher_ids) selected(id)
    left join public.profiles p on p.id=selected.id
    where p.id is null or p.role not in ('admin','teacher','manager') or not p.is_active
  ) then raise exception '선택한 담당 선생님 계정을 확인해 주세요.'; end if;
  if coalesce(jsonb_typeof(p_schedules),'')<>'array' or jsonb_array_length(p_schedules)=0 then
    raise exception '수업 요일과 시간을 입력해 주세요.';
  end if;

  select s.* into subject_row from public.academy_subjects s
  where s.id=p_subject_id and s.active limit 1;
  if subject_row.id is null then raise exception '사용 가능한 과목을 선택해 주세요.'; end if;
  if exists(
    select 1 from public.classes c
    where c.id<>p_class_id and c.active
      and lower(regexp_replace(c.name,'\s+','','g'))=lower(regexp_replace(trim(p_name),'\s+','','g'))
  ) then raise exception '같은 이름의 클래스가 이미 있습니다.'; end if;

  update public.classes c set
    name=trim(p_name), subject=subject_row.name, subject_id=subject_row.id,
    room=nullif(trim(p_room),''), color=coalesce(nullif(trim(p_color),''),'#922D61')
  where c.id=p_class_id;
  if not found then raise exception '클래스를 찾을 수 없습니다.'; end if;

  delete from public.class_schedules cs where cs.class_id=p_class_id;
  delete from public.class_teachers ct where ct.class_id=p_class_id;
  insert into public.class_teachers(class_id,profile_id)
  select p_class_id,id from unnest(normalized_teacher_ids) selected(id);

  for schedule_row in select value from jsonb_array_elements(p_schedules)
  loop
    if (schedule_row->>'weekday')::smallint not between 1 and 7 then
      raise exception '수업 요일을 확인해 주세요.';
    end if;
    if (schedule_row->>'startTime')::time >= (schedule_row->>'endTime')::time then
      raise exception '종료 시간은 시작 시간보다 늦어야 합니다.';
    end if;
    insert into public.class_schedules(class_id,weekday,start_time,end_time)
    values(
      p_class_id,
      (schedule_row->>'weekday')::smallint,
      (schedule_row->>'startTime')::time,
      (schedule_row->>'endTime')::time
    );
  end loop;
end
$$;

revoke all on function public.staff_save_class_schedule(uuid,uuid,smallint,time,time,uuid[]) from public;
revoke all on function public.staff_create_class_with_schedules(text,uuid,text,text,jsonb,uuid[]) from public;
revoke all on function public.staff_update_class_with_teachers(uuid,text,uuid,text,text,jsonb,uuid[]) from public;
grant execute on function public.staff_save_class_schedule(uuid,uuid,smallint,time,time,uuid[]) to authenticated;
grant execute on function public.staff_create_class_with_schedules(text,uuid,text,text,jsonb,uuid[]) to authenticated;
grant execute on function public.staff_update_class_with_teachers(uuid,text,uuid,text,text,jsonb,uuid[]) to authenticated;

notify pgrst,'reload schema';
