do $test$
declare a uuid;b uuid;eid uuid;ver uuid;cat text;v jsonb;d date:=(now() at time zone 'Asia/Seoul')::date;
begin
 select id into a from public.profiles where is_active and role='admin' limit 1;
 select id into b from public.profiles where is_active and role='teacher' and id<>a limit 1;
 if a is null or b is null then raise exception 'Missing fixtures';end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 select id into cat from public.academic_calendar_categories where scope='academy' and is_active limit 1;
 eid:=public.staff_save_calendar_with_reminder(jsonb_build_object('p_scope','academy','p_category',cat,'p_title','Dismiss rollback test','p_starts_on',d,'p_ends_on',d,'p_teacher_id',a,'p_status','scheduled','p_reminder_recipient_ids',jsonb_build_array(a,b)),true);
 select reminder_version into ver from public.academic_calendar_events where id=eid;
 begin perform public.staff_dismiss_schedule_reminder('calendar',eid,ver);raise exception 'Unread deleted';exception when others then if sqlerrm='Unread deleted' then raise;end if;end;
 perform public.staff_ack_schedule_reminder('calendar',eid,ver);
 perform public.staff_dismiss_schedule_reminder('calendar',eid,ver);
 perform public.staff_dismiss_schedule_reminder('calendar',eid,ver);
 if exists(select 1 from jsonb_array_elements(public.staff_schedule_reminders(true)->'items') x where x->>'id'=eid::text) then raise exception 'Deleted reminder reappeared';end if;
 if exists(select 1 from jsonb_array_elements_text(public.staff_schedule_reminders(true)->'popup') x where x='calendar:'||eid||':'||ver) then raise exception 'Deleted popup reappeared';end if;
 if not exists(select 1 from public.academic_calendar_events where id=eid) then raise exception 'Original schedule deleted';end if;
 perform set_config('request.jwt.claim.sub',b::text,true);
 if not exists(select 1 from jsonb_array_elements(public.staff_schedule_reminders(false)->'items') x where x->>'id'=eid::text) then raise exception 'Other recipient lost reminder';end if;
 if (select dismissed_at from public.schedule_reminder_receipts where profile_id=b and source_id=eid) is not null then raise exception 'Other recipient receipt modified';end if;
 perform set_config('request.jwt.claim.sub',a::text,true);
 select public.calendar_edit_values(e) into v from public.academic_calendar_events e where id=eid;
 perform public.staff_patch_calendar_event(eid,v,jsonb_build_object('note','New information'));
 if not exists(select 1 from jsonb_array_elements(public.staff_schedule_reminders(false)->'items') x where x->>'id'=eid::text) then raise exception 'Changed schedule notification suppressed';end if;
 perform set_config('request.jwt.claim.sub','',true);
 begin perform public.staff_dismiss_schedule_reminder('calendar',eid,ver);raise exception 'Anonymous delete accepted';exception when others then if sqlerrm='Anonymous delete accepted' then raise;end if;end;
 if has_function_privilege('anon','public.staff_dismiss_schedule_reminder(text,uuid,uuid)','EXECUTE') then raise exception 'Anonymous grant';end if;
end $test$;
select 'dismiss checks passed' as result;
