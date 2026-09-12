-- Preserve existing authorization/validation; compare under the same write lock.
create function public.settings_edit_conflicts(p_base jsonb,p_current jsonb,p_changes jsonb) returns jsonb
language plpgsql immutable set search_path=public as $$
declare k text; conflicts jsonb:='[]';
begin
 if jsonb_typeof(p_base) is distinct from 'object' or jsonb_typeof(p_changes) is distinct from 'object' then raise exception '수정 기준이 없습니다. 화면을 다시 열어 주세요.'; end if;
 for k in select jsonb_object_keys(p_changes) loop
   if not p_current ? k or not p_base ? k then raise exception '수정 항목을 확인해 주세요.'; end if;
   if p_current->k is distinct from p_base->k and p_current->k is distinct from p_changes->k then conflicts:=conflicts||to_jsonb(k); end if;
 end loop;
 return conflicts;
end $$;
revoke all on function public.settings_edit_conflicts(jsonb,jsonb,jsonb) from public,anon,authenticated;

create function public.calendar_edit_values(e public.academic_calendar_events) returns jsonb
language sql immutable set search_path=public as $$
 select jsonb_build_object(
 'kind',jsonb_build_object('scope',e.event_scope,'category',e.category),
 'timing',jsonb_build_object('startsOn',e.starts_on::text,'endsOn',e.ends_on::text,'startsAt',coalesce(to_char(e.starts_at,'HH24:MI'),''),'endsAt',coalesce(to_char(e.ends_at,'HH24:MI'),'')),
 'school',coalesce(e.school,''),'grade',coalesce(e.grade,''),'title',e.title,
 'classId',coalesce(e.class_id::text,''),'teacherId',coalesce(e.teacher_profile_id::text,''),
 'note',coalesce(e.note,''),'contactName',coalesce(e.contact_name,''),'contactPhone',coalesce(e.contact_phone,''),
 'location',coalesce(e.location,''),'status',e.status)
$$;
revoke all on function public.calendar_edit_values(public.academic_calendar_events) from public,anon,authenticated;

create function public.staff_patch_calendar_event(p_id uuid,p_base jsonb,p_changes jsonb,p_delete boolean default false) returns jsonb
language plpgsql security definer set search_path=public as $$
declare e public.academic_calendar_events; v jsonb; conflicts jsonb; m jsonb;
begin
 if auth.uid() is null or not coalesce(public.is_staff(),false) or public.current_user_role()='assistant' then raise exception '일정 수정 권한이 없습니다.'; end if;
 select * into e from public.academic_calendar_events where id=p_id for update;
 if not found then raise exception '이미 삭제된 일정입니다. 입력 내용은 유지됩니다.'; end if;
 if e.created_by<>auth.uid() and public.current_user_role()<>'admin' then raise exception '일정 수정 권한이 없습니다.'; end if;
 v:=public.calendar_edit_values(e);
 conflicts:=public.settings_edit_conflicts(p_base,v,case when p_delete then p_base else p_changes end);
 if jsonb_array_length(conflicts)>0 then return jsonb_build_object('conflicts',conflicts,'values',v); end if;
 if p_delete then perform public.staff_delete_academic_calendar_event(p_id); return jsonb_build_object('saved',true); end if;
 m:=v||p_changes;
 perform public.staff_save_calendar_event(p_id,m#>>'{kind,scope}',m->>'school',m->>'grade',m#>>'{kind,category}',m->>'title',
 (m#>>'{timing,startsOn}')::date,(m#>>'{timing,endsOn}')::date,nullif(m#>>'{timing,startsAt}','')::time,nullif(m#>>'{timing,endsAt}','')::time,
 nullif(m->>'classId','')::uuid,nullif(m->>'teacherId','')::uuid,m->>'note',m->>'contactName',m->>'contactPhone',m->>'location',m->>'status');
 return jsonb_build_object('saved',true);
end $$;
revoke all on function public.staff_patch_calendar_event(uuid,jsonb,jsonb,boolean) from public,anon;
grant execute on function public.staff_patch_calendar_event(uuid,jsonb,jsonb,boolean) to authenticated;

create function public.class_settings_values(p_id uuid) returns jsonb language sql stable set search_path=public as $$
 select jsonb_build_object('name',c.name,'subjectId',coalesce(c.subject_id::text,''),'room',coalesce(c.room,''),'color',c.color,
 'teacherIds',coalesce((select jsonb_agg(profile_id::text order by profile_id) from public.class_teachers where class_id=c.id),'[]'::jsonb),
 'schedules',coalesce((select jsonb_agg(jsonb_build_object('weekday',weekday,'startTime',to_char(start_time,'HH24:MI'),'endTime',to_char(end_time,'HH24:MI')) order by weekday,start_time,end_time)
 from public.class_schedules where class_id=c.id and (valid_until is null or valid_until>=current_date)),'[]'::jsonb))
 from public.classes c where c.id=p_id
$$;
revoke all on function public.class_settings_values(uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.staff_update_class_with_teachers(p_class_id uuid, p_name text, p_subject_id uuid, p_room text, p_color text, p_schedules jsonb, p_teacher_ids uuid[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  schedule_row jsonb;
  normalized_teacher_ids uuid[];
  personal_schedule_student_ids uuid[];
  subject_row public.academy_subjects%rowtype;
begin
  perform pg_advisory_xact_lock(hashtext('hansalmae_class_schedule_save'));
  perform 1 from public.classes where id=p_class_id for update;
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
    where p.id is null or p.role not in ('admin','teacher','sub_admin','manager') or not p.is_active
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

  -- Keep schedule IDs and individual enrollments for unchanged slots.
  if exists(select 1 from public.student_schedule_assignments ssa
    join public.class_schedules cs on cs.id=ssa.class_schedule_id
    where cs.class_id=p_class_id and (cs.valid_until is null or cs.valid_until>=current_date) and not exists(
      select 1 from jsonb_array_elements(p_schedules) x
      where (x->>'weekday')::int=cs.weekday and (x->>'startTime')::time=cs.start_time and (x->>'endTime')::time=cs.end_time
    )) then raise exception '개별 수강요일이 배정된 시간이 포함되어 있습니다. 학생의 수강요일을 먼저 조정한 뒤 시간을 변경해 주세요.'; end if;

  update public.classes c set
    name=trim(p_name), subject=subject_row.name, subject_id=subject_row.id,
    room=nullif(trim(p_room),''), color=coalesce(nullif(trim(p_color),''),'#922D61')
  where c.id=p_class_id;
  if not found then raise exception '클래스를 찾을 수 없습니다.'; end if;

  delete from public.class_schedules cs where cs.class_id=p_class_id and (cs.valid_until is null or cs.valid_until>=current_date) and not exists(select 1 from jsonb_array_elements(p_schedules) x where (x->>'weekday')::int=cs.weekday and (x->>'startTime')::time=cs.start_time and (x->>'endTime')::time=cs.end_time);
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
    if not exists(select 1 from public.class_schedules cs where cs.class_id=p_class_id and (cs.valid_until is null or cs.valid_until>=current_date) and cs.weekday=(schedule_row->>'weekday')::int and cs.start_time=(schedule_row->>'startTime')::time and cs.end_time=(schedule_row->>'endTime')::time) then
    insert into public.class_schedules(class_id,weekday,start_time,end_time)
    values(
      p_class_id,
      (schedule_row->>'weekday')::smallint,
      (schedule_row->>'startTime')::time,
      (schedule_row->>'endTime')::time
    );
    end if;
  end loop;

end
$function$;

create function public.staff_patch_class_settings(p_id uuid,p_base jsonb,p_changes jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v jsonb; m jsonb; conflicts jsonb;
begin
 if auth.uid() is null or not coalesce(public.is_staff(),false) then raise exception '클래스 수정 권한이 없습니다.'; end if;
 perform pg_advisory_xact_lock(hashtext('hansalmae_class_schedule_save'));
 perform 1 from public.classes where id=p_id and active for update;
 if not found then raise exception '운영 중인 클래스를 찾을 수 없습니다.'; end if;
 if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_id and profile_id=auth.uid()) then raise exception '담당 클래스만 수정할 수 있습니다.'; end if;
 v:=public.class_settings_values(p_id); conflicts:=public.settings_edit_conflicts(p_base,v,p_changes);
 if jsonb_array_length(conflicts)>0 then return jsonb_build_object('conflicts',conflicts,'values',v); end if;
 m:=v||p_changes;
 perform public.staff_update_class_with_teachers(p_id,m->>'name',(m->>'subjectId')::uuid,m->>'room',m->>'color',m->'schedules',array(select jsonb_array_elements_text(m->'teacherIds')::uuid));
 return jsonb_build_object('saved',true);
end $$;
revoke all on function public.staff_patch_class_settings(uuid,jsonb,jsonb) from public,anon;
grant execute on function public.staff_patch_class_settings(uuid,jsonb,jsonb) to authenticated;
create function public.staff_guard_class_schedule(p_id uuid,p_class_id uuid,p_base jsonb,p_values jsonb,p_delete boolean default false) returns uuid
language plpgsql security definer set search_path=public as $$
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
end $$;
revoke all on function public.staff_guard_class_schedule(uuid,uuid,jsonb,jsonb,boolean) from public,anon;
grant execute on function public.staff_guard_class_schedule(uuid,uuid,jsonb,jsonb,boolean) to authenticated;
create function public.staff_class_schedule_create_base(p_class_id uuid) returns jsonb
language plpgsql stable security definer set search_path=public as $$
begin
 if auth.uid() is null or not coalesce(public.is_staff(),false) then raise exception '수업 배정 권한이 없습니다.'; end if;
 return jsonb_build_object('teacherIds',coalesce((select jsonb_agg(profile_id::text order by profile_id) from public.class_teachers where class_id=p_class_id),'[]'::jsonb));
end $$;
revoke all on function public.staff_class_schedule_create_base(uuid) from public,anon;
grant execute on function public.staff_class_schedule_create_base(uuid) to authenticated;
