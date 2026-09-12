-- Execute inside BEGIN / ROLLBACK after loading the migration.
do $$
declare uid uuid; eid uuid; cid uuid; base jsonb; latest jsonb; r jsonb; before_ids jsonb; after_ids jsonb; before_choices jsonb; after_choices jsonb; sid uuid; sb jsonb;
begin
 select id into uid from public.profiles where role::text='admin' and is_active limit 1;
 perform set_config('request.jwt.claim.sub',uid::text,true);
 select id,public.calendar_edit_values(e) into eid,base from public.academic_calendar_events e limit 1;
 if eid is null then raise exception 'calendar fixture missing'; end if;
 r:=public.staff_patch_calendar_event(eid,base,jsonb_build_object('note','concurrency verification'));
 r:=public.staff_patch_calendar_event(eid,base,jsonb_build_object('title',base->>'title'||' verification'));
 select public.calendar_edit_values(e) into latest from public.academic_calendar_events e where id=eid;
 if latest->>'note'<>'concurrency verification' or latest->>'title'<>base->>'title'||' verification' then raise exception 'disjoint calendar merge failed'; end if;
 r:=public.staff_patch_calendar_event(eid,base,jsonb_build_object('note','stale'));
 if not (r->'conflicts') ? 'note' then raise exception 'calendar conflict missing'; end if;
 r:=public.staff_patch_calendar_event(eid,base,'{}',true);
 if jsonb_array_length(r->'conflicts')=0 then raise exception 'stale calendar delete passed'; end if;
 select c.id into cid from public.classes c where c.active and c.subject_id is not null
 and exists(select 1 from public.class_schedules cs join public.student_schedule_assignments ssa on ssa.class_schedule_id=cs.id where cs.class_id=c.id and (cs.valid_until is null or cs.valid_until>=current_date))
 and not exists(select 1 from public.class_teachers ct join public.profiles p on p.id=ct.profile_id where ct.class_id=c.id and not p.is_active)
 limit 1;
 if cid is null then raise exception 'class fixture missing'; end if;
 base:=public.class_settings_values(cid);
 select jsonb_agg(id order by id) into before_ids from public.class_schedules where class_id=cid;
 select coalesce(jsonb_agg(to_jsonb(ssa) order by ssa.student_id,ssa.class_schedule_id),'[]'::jsonb) into before_choices from public.student_schedule_assignments ssa join public.class_schedules cs on cs.id=ssa.class_schedule_id where cs.class_id=cid;
 r:=public.staff_patch_class_settings(cid,base,jsonb_build_object('name',base->>'name'||' verification'));
 r:=public.staff_patch_class_settings(cid,base,jsonb_build_object('color','#123456'));
 latest:=public.class_settings_values(cid);
 if latest->>'name'<>base->>'name'||' verification' or latest->>'color'<>'#123456' then raise exception 'disjoint class merge failed'; end if;
 select jsonb_agg(id order by id) into after_ids from public.class_schedules where class_id=cid;
 select coalesce(jsonb_agg(to_jsonb(ssa) order by ssa.student_id,ssa.class_schedule_id),'[]'::jsonb) into after_choices from public.student_schedule_assignments ssa join public.class_schedules cs on cs.id=ssa.class_schedule_id where cs.class_id=cid;
 if before_ids is distinct from after_ids or before_choices is distinct from after_choices then raise exception 'schedule IDs or individual enrollment changed'; end if;
 r:=public.staff_patch_class_settings(cid,base,jsonb_build_object('name','stale'));
 if not (r->'conflicts') ? 'name' then raise exception 'class conflict missing'; end if;
 select cs.id,jsonb_build_object('weekday',weekday,'startTime',to_char(start_time,'HH24:MI'),'endTime',to_char(end_time,'HH24:MI'),'teacherIds',latest->'teacherIds') into sid,sb from public.class_schedules cs where cs.class_id=cid limit 1;
 begin
 perform public.staff_guard_class_schedule(sid,cid,sb||jsonb_build_object('weekday',0),'{}',true);
 raise exception 'stale schedule delete passed';
 exception when others then if sqlerrm='stale schedule delete passed' then raise; end if; end;
 perform set_config('request.jwt.claim.sub','',true);
 begin
 perform public.staff_patch_class_settings(cid,base,'{}');
 raise exception 'anonymous save passed';
 exception when others then if sqlerrm='anonymous save passed' then raise; end if; end;
end $$;
