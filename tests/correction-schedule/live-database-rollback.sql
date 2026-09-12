-- Run after the live-update migration, inside BEGIN / ROLLBACK.
do $$
declare v_staff uuid; v_id uuid; v_day text; v_full jsonb; v_delta jsonb; v_expected jsonb;
begin
 select id into v_staff from public.profiles where role::text='admin' limit 1;
 perform set_config('request.jwt.claim.sub',v_staff::text,true);
 select id,valid_from::text into v_id,v_day from public.correction_assignments where active and subject is not null limit 1;
 if v_id is null then raise exception 'fixture missing'; end if;
 v_full:=public.correction_management_board_v2(v_day);
 v_delta:=public.correction_timetable_updates(v_day,array[v_id]);
 select coalesce(jsonb_agg(x),'[]'::jsonb) into v_expected from jsonb_array_elements(v_full->'assignments') x where x->>'id'=v_id::text;
 if v_delta->'assignments'<>v_expected then raise exception 'delta differs from board'; end if;
 if v_delta ? 'students' or v_delta ? 'staff' then raise exception 'unexpected roster reload'; end if;
 update public.correction_assignments set note=coalesce(note,'') where id=v_id;
 if not exists(select 1 from public.correction_timetable_signals where assignment_id=v_id) then raise exception 'signal missing'; end if;
 if public.correction_timetable_updates(v_day,array[]::uuid[])->'assignments'<>'[]'::jsonb then raise exception 'empty ids returns data'; end if;
 perform set_config('request.jwt.claim.sub','',true);
 begin
   perform public.correction_timetable_updates(v_day,array[v_id]);
   raise exception 'unauthorized call passed';
 exception when others then
   if sqlerrm='unauthorized call passed' then raise; end if;
 end;
end $$;
