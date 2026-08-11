-- 수업 저장을 직렬화하고 충돌한 교사·교실·수업명을 구체적으로 안내합니다.

create or replace function public.staff_save_class_schedule(
  p_schedule_id uuid,
  p_class_id uuid,
  p_weekday smallint,
  p_start_time time,
  p_end_time time,
  p_teacher_ids uuid[]
)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  saved_id uuid;
  teacher_id uuid;
  target_room text;
  target_class_name text;
  teacher_conflicts text;
  room_conflict text;
begin
  if not coalesce(public.is_staff(),false) then raise exception '교직원만 수업을 배정할 수 있습니다.'; end if;
  if p_weekday not between 1 and 6 then raise exception '수업 요일을 확인해 주세요.'; end if;
  if p_start_time>=p_end_time then raise exception '종료 시간은 시작 시간보다 늦어야 합니다.'; end if;
  if coalesce(array_length(p_teacher_ids,1),0)=0 then raise exception '담당 선생님을 한 명 이상 선택해 주세요.'; end if;
  select nullif(trim(room),''),name into target_room,target_class_name from public.classes where id=p_class_id and active;
  if target_class_name is null then raise exception '운영 중인 클래스를 찾을 수 없습니다.'; end if;

  perform pg_advisory_xact_lock(hashtext('hansalmae_class_schedule_save'));

  if exists(select 1 from public.class_schedules cs where cs.class_id=p_class_id and cs.weekday=p_weekday and cs.start_time<p_end_time and cs.end_time>p_start_time and cs.id<>coalesce(p_schedule_id,'00000000-0000-0000-0000-000000000000'::uuid)) then
    raise exception '클래스 시간 충돌: %에 같은 시간대 배정이 이미 있습니다.',target_class_name;
  end if;

  select string_agg(distinct p.display_name||' · '||c.name||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI'),' / ' order by p.display_name||' · '||c.name||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI'))
  into teacher_conflicts
  from unnest(p_teacher_ids) selected_teacher(id)
  join public.profiles p on p.id=selected_teacher.id
  join public.class_teachers ct on ct.profile_id=selected_teacher.id and ct.class_id<>p_class_id
  join public.class_schedules cs on cs.class_id=ct.class_id
  join public.classes c on c.id=cs.class_id
  where cs.weekday=p_weekday and cs.start_time<p_end_time and cs.end_time>p_start_time and cs.id<>coalesce(p_schedule_id,'00000000-0000-0000-0000-000000000000'::uuid);
  if teacher_conflicts is not null then raise exception '교사 시간 충돌: %',teacher_conflicts; end if;

  if target_room is not null then
    select c.name||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI') into room_conflict
    from public.class_schedules cs join public.classes c on c.id=cs.class_id
    where cs.weekday=p_weekday and cs.start_time<p_end_time and cs.end_time>p_start_time and cs.id<>coalesce(p_schedule_id,'00000000-0000-0000-0000-000000000000'::uuid) and nullif(trim(c.room),'')=target_room
    order by cs.start_time limit 1;
    if room_conflict is not null then raise exception '교실 시간 충돌: % 강의실에 % 수업이 있습니다.',target_room,room_conflict; end if;
  end if;

  delete from public.class_teachers where class_id=p_class_id;
  if p_schedule_id is null then
    insert into public.class_schedules(class_id,weekday,start_time,end_time) values(p_class_id,p_weekday,p_start_time,p_end_time) returning id into saved_id;
  else
    update public.class_schedules set weekday=p_weekday,start_time=p_start_time,end_time=p_end_time where id=p_schedule_id and class_id=p_class_id returning id into saved_id;
    if saved_id is null then raise exception '수업 배정을 찾을 수 없습니다.'; end if;
  end if;
  foreach teacher_id in array p_teacher_ids loop insert into public.class_teachers(class_id,profile_id) values(p_class_id,teacher_id); end loop;
  return saved_id;
end
$$;

revoke all on function public.staff_save_class_schedule(uuid,uuid,smallint,time,time,uuid[]) from public;
grant execute on function public.staff_save_class_schedule(uuid,uuid,smallint,time,time,uuid[]) to authenticated;
