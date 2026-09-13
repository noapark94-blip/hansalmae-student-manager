create or replace function public.staff_claim_record_reminder() returns jsonb
language plpgsql security definer set search_path=public as $$
declare today date:=(now() at time zone 'Asia/Seoul')::date; items jsonb; phase text; claimed integer; requested text; due_count integer;
begin
 items:=public.staff_record_worklist(today-6,today);
 select count(*),max(i->>'requestedAt') into due_count,requested from jsonb_array_elements(items) i
 where (i->>'due')::boolean and exists(select 1 from jsonb_array_elements(i->'owners') o where o->>'id'=auth.uid()::text);
 if due_count=0 then return null;end if;
 phase:=case when (now() at time zone 'Asia/Seoul')::time>='21:30' then 'closing' else 'after-class' end;
 if requested is not null and requested::timestamptz>now()-interval '1 day' then
   insert into public.record_work_receipts(profile_id,day,phase) values(auth.uid(),today,'request:'||requested) on conflict do nothing;
   get diagnostics claimed=row_count;
   if claimed>0 then
     -- A manual request also covers this time slot, but never consumes the later closing slot.
     insert into public.record_work_receipts(profile_id,day,phase) values(auth.uid(),today,phase) on conflict do nothing;
     return jsonb_build_object('count',due_count,'requested',true);
   end if;
 end if;
 insert into public.record_work_receipts(profile_id,day,phase) values(auth.uid(),today,phase) on conflict do nothing;
 get diagnostics claimed=row_count;
 return case when claimed>0 then jsonb_build_object('count',due_count,'requested',phase like 'request:%') else null end;
end $$;
revoke all on function public.staff_claim_record_reminder() from public,anon;
grant execute on function public.staff_claim_record_reminder() to authenticated;
notify pgrst,'reload schema';
