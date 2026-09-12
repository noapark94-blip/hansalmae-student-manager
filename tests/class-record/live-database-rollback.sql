-- Execute after migration inside BEGIN / ROLLBACK.
do $$
declare uid uuid; eid uuid; yr int; cid uuid; lid uuid; dt date; full_data jsonb; delta jsonb; expected jsonb;
begin
 select id into uid from public.profiles where role::text='admin' and is_active limit 1;
 perform set_config('request.jwt.claim.sub',uid::text,true);
 select id,extract(year from starts_on)::int into eid,yr from public.academic_calendar_events limit 1;
 if eid is null then raise exception 'calendar fixture missing';end if;
 update public.academic_calendar_events set note=note where id=eid;
 if not exists(select 1 from public.staff_live_signals where key='calendar:'||eid::text) then raise exception 'calendar signal missing';end if;
 full_data:=public.staff_academic_calendar_board(yr);
 delta:=public.staff_academic_calendar_updates(yr,array[eid]);
 select jsonb_agg(x) into expected from jsonb_array_elements(full_data->'events') x where x->>'id'=eid::text;
 if delta->'events' is distinct from expected or delta ? 'students' or delta ? 'classes' then raise exception 'calendar delta mismatch';end if;
 delete from public.academic_calendar_events where id=eid;
 if public.staff_academic_calendar_updates(yr,array[eid])->'events'<>'[]'::jsonb then raise exception 'calendar deletion not reconciled';end if;
 select id,class_id,lesson_date into lid,cid,dt from public.lessons where class_id is not null limit 1;
 if lid is null then raise exception 'lesson fixture missing';end if;
 update public.lessons set updated_at=updated_at where id=lid;
 update public.classes set name=name where id=cid;
 if not exists(select 1 from public.staff_live_signals where key='record:'||cid::text||':'||dt::text) then raise exception 'record signal missing';end if;
 if not exists(select 1 from public.staff_live_signals where key='classes:'||cid::text) then raise exception 'class signal missing';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
 execute 'set local role authenticated';
 if exists(select 1 from public.staff_live_signals) then raise exception 'nonstaff saw signals';end if;
 execute 'reset role';
end $$;
