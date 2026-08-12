-- 클래스 담당자 선택과 학생별 주간 시간표
create or replace function public.staff_class_teacher_options()
returns jsonb language sql stable security definer set search_path=public as $$
  select case when public.is_staff() then coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name),'[]'::jsonb) else '[]'::jsonb end
  from public.profiles p where p.role in ('admin','teacher') and p.is_active and (public.current_user_role()='admin' or p.id=auth.uid());
$$;

-- 기존 저장 함수의 월~토 제한을 월~일로 확장합니다.
create or replace function public.staff_save_class_schedule(
  p_schedule_id uuid,p_class_id uuid,p_weekday smallint,p_start_time time,p_end_time time,p_teacher_ids uuid[]
) returns uuid language plpgsql security definer set search_path=public as $$
declare saved_id uuid; teacher_id uuid; target_room text; target_class_name text; teacher_conflicts text; room_conflict text;
begin
  if not coalesce(public.is_staff(),false) then raise exception '교직원만 수업을 배정할 수 있습니다.'; end if;
  if p_weekday not between 1 and 7 then raise exception '수업 요일을 확인해 주세요.'; end if;
  if p_start_time>=p_end_time then raise exception '종료 시간은 시작 시간보다 늦어야 합니다.'; end if;
  if coalesce(array_length(p_teacher_ids,1),0)=0 then raise exception '담당 선생님을 한 명 이상 선택해 주세요.'; end if;
  select nullif(trim(room),''),name into target_room,target_class_name from public.classes where id=p_class_id and active;
  if target_class_name is null then raise exception '운영 중인 클래스를 찾을 수 없습니다.'; end if;
  perform pg_advisory_xact_lock(hashtext('hansalmae_class_schedule_save'));
  if exists(select 1 from public.class_schedules cs where cs.class_id=p_class_id and cs.weekday=p_weekday and cs.start_time<p_end_time and cs.end_time>p_start_time and cs.id<>coalesce(p_schedule_id,'00000000-0000-0000-0000-000000000000'::uuid)) then
    raise exception '클래스 시간 충돌: %에 같은 시간대 배정이 이미 있습니다.',target_class_name;
  end if;
  select string_agg(distinct p.display_name||' · '||c.name||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI'),' / ' order by p.display_name||' · '||c.name||' '||to_char(cs.start_time,'HH24:MI')||'–'||to_char(cs.end_time,'HH24:MI')) into teacher_conflicts
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
end $$;

create or replace function public.staff_create_class_with_teachers(
  p_name text,p_subject_id uuid,p_room text,p_color text,p_schedules jsonb,p_teacher_ids uuid[]
) returns uuid language plpgsql security definer set search_path=public as $$
declare result_id uuid; schedule_row jsonb; teacher_ids uuid[];
begin
  if not public.is_staff() then raise exception '교직원만 클래스를 만들 수 있습니다.'; end if;
  teacher_ids:=array(select distinct id from unnest(coalesce(p_teacher_ids,'{}')) id);
  if coalesce(array_length(teacher_ids,1),0)=0 then raise exception '담당 선생님을 한 명 이상 선택해 주세요.'; end if;
  if public.current_user_role()<>'admin' and (array_length(teacher_ids,1)<>1 or teacher_ids[1]<>auth.uid()) then raise exception '선생님은 본인 담당 클래스로만 만들 수 있습니다.'; end if;
  if exists(select 1 from unnest(teacher_ids) id left join public.profiles p on p.id=id where p.id is null or p.role not in ('admin','teacher')) then raise exception '선택한 담당 선생님 계정을 확인해 주세요.'; end if;
  if coalesce(jsonb_typeof(p_schedules),'')<>'array' or jsonb_array_length(p_schedules)=0 then raise exception '수업 요일과 시간을 입력해 주세요.'; end if;
  result_id:=public.staff_create_my_class(p_name,p_subject_id,p_room,p_color);
  delete from public.class_teachers where class_id=result_id;
  insert into public.class_teachers(class_id,profile_id) select result_id,id from unnest(teacher_ids) id;
  for schedule_row in select value from jsonb_array_elements(p_schedules) loop
    perform public.staff_save_class_schedule(null,result_id,(schedule_row->>'weekday')::smallint,(schedule_row->>'startTime')::time,(schedule_row->>'endTime')::time,teacher_ids);
  end loop;
  return result_id;
end $$;

create or replace function public.staff_update_class_with_teachers(
  p_class_id uuid,p_name text,p_subject_id uuid,p_room text,p_color text,p_schedules jsonb,p_teacher_ids uuid[]
) returns void language plpgsql security definer set search_path=public as $$
declare schedule_row jsonb; teacher_ids uuid[];
begin
  if not public.is_staff() or (public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid())) then raise exception '담당 클래스만 수정할 수 있습니다.'; end if;
  teacher_ids:=array(select distinct id from unnest(coalesce(p_teacher_ids,'{}')) id);
  if coalesce(array_length(teacher_ids,1),0)=0 then raise exception '담당 선생님을 한 명 이상 선택해 주세요.'; end if;
  if public.current_user_role()<>'admin' and not auth.uid()=any(teacher_ids) then raise exception '본인을 담당 선생님에서 제외할 수 없습니다.'; end if;
  if exists(select 1 from unnest(teacher_ids) id left join public.profiles p on p.id=id where p.id is null or p.role not in ('admin','teacher')) then raise exception '선택한 담당 선생님 계정을 확인해 주세요.'; end if;
  if coalesce(jsonb_typeof(p_schedules),'')<>'array' or jsonb_array_length(p_schedules)=0 then raise exception '수업 요일과 시간을 입력해 주세요.'; end if;
  perform public.staff_update_class(p_class_id,p_name,p_subject_id,p_room,p_color);
  delete from public.class_schedules where class_id=p_class_id;
  delete from public.class_teachers where class_id=p_class_id;
  insert into public.class_teachers(class_id,profile_id) select p_class_id,id from unnest(teacher_ids) id;
  for schedule_row in select value from jsonb_array_elements(p_schedules) loop
    perform public.staff_save_class_schedule(null,p_class_id,(schedule_row->>'weekday')::smallint,(schedule_row->>'startTime')::time,(schedule_row->>'endTime')::time,teacher_ids);
  end loop;
end $$;

create or replace function public.staff_class_management_board()
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception '교직원만 클래스 목록을 확인할 수 있습니다.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',c.id,'name',c.name,'subject',c.subject,'subjectId',c.subject_id,'room',c.room,'color',c.color,'active',c.active,
    'schedules',coalesce((select jsonb_agg(jsonb_build_object('id',cs.id,'weekday',cs.weekday,'startTime',cs.start_time,'endTime',cs.end_time) order by cs.weekday,cs.start_time) from public.class_schedules cs where cs.class_id=c.id and (cs.valid_until is null or cs.valid_until>=current_date)),'[]'::jsonb),
    'teachers',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name) from public.class_teachers ct join public.profiles p on p.id=ct.profile_id where ct.class_id=c.id),'[]'::jsonb),
    'enrollmentCount',(select count(*) from public.enrollments e where e.class_id=c.id),'scheduleCount',(select count(*) from public.class_schedules cs where cs.class_id=c.id),'lessonCount',(select count(*) from public.lessons l where l.class_id=c.id),'assignmentCount',(select count(*) from public.assignments a where a.class_id=c.id)
  ) order by c.active desc,c.subject,c.name) from public.classes c where public.current_user_role()='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid())),'[]'::jsonb);
end $$;

create or replace function public.staff_student_weekly_timetables()
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if not public.is_staff() then raise exception '교직원만 학생 시간표를 확인할 수 있습니다.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('studentId',s.id,'rows',coalesce((select jsonb_agg(jsonb_build_object(
    'id',cs.id,'weekday',cs.weekday,'startTime',cs.start_time,'endTime',cs.end_time,'className',c.name,'subject',c.subject,'color',c.color,'room',c.room,
    'teachers',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name)) from public.class_teachers ct join public.profiles p on p.id=ct.profile_id where ct.class_id=c.id),'[]'::jsonb)
  ) order by cs.weekday,cs.start_time) from public.enrollments e join public.classes c on c.id=e.class_id join public.class_schedules cs on cs.class_id=c.id where e.student_id=s.id and e.status='active' and c.active and (not exists(select 1 from public.student_schedule_assignments x where x.student_id=s.id) or exists(select 1 from public.student_schedule_assignments x where x.student_id=s.id and x.class_schedule_id=cs.id))),'[]'::jsonb))) from public.students s),'[]'::jsonb);
end $$;

revoke all on function public.staff_class_teacher_options(),public.staff_create_class_with_teachers(text,uuid,text,text,jsonb,uuid[]),public.staff_update_class_with_teachers(uuid,text,uuid,text,text,jsonb,uuid[]),public.staff_student_weekly_timetables() from public;
grant execute on function public.staff_class_teacher_options(),public.staff_create_class_with_teachers(text,uuid,text,text,jsonb,uuid[]),public.staff_update_class_with_teachers(uuid,text,uuid,text,text,jsonb,uuid[]),public.staff_student_weekly_timetables(),public.staff_class_management_board() to authenticated;
notify pgrst,'reload schema';
