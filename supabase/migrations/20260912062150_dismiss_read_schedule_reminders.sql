alter table public.schedule_reminder_receipts add column dismissed_at timestamptz;
CREATE OR REPLACE FUNCTION public.staff_schedule_reminders(p_claim boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare popup jsonb:='[]';items jsonb;begin
 if auth.uid() is null or not public.is_staff() then raise exception '교직원만 확인할 수 있습니다.';end if;
 if p_claim then
 with claimed as(insert into public.schedule_reminder_receipts(profile_id,source,source_id,version)
 select auth.uid(),r.source,r.source_id,r.version from public.current_schedule_reminders() r where r.due=(now() at time zone 'Asia/Seoul')::date
 on conflict do nothing returning source,source_id,version)
 select coalesce(jsonb_agg(c.source||':'||c.source_id||':'||c.version),'[]') into popup from claimed c;
 end if;
 select coalesce(jsonb_agg(r.payload||jsonb_build_object('read',receipt.read_at is not null) order by r.due desc,r.payload->>'time' nulls last,r.source_id),'[]') into items
 from public.current_schedule_reminders() r left join public.schedule_reminder_receipts receipt on receipt.profile_id=auth.uid() and receipt.source=r.source and receipt.source_id=r.source_id and receipt.version=r.version
 where receipt.dismissed_at is null;
 return jsonb_build_object('items',items,'popup',popup);end $function$
;
create function public.staff_dismiss_schedule_reminder(p_source text,p_id uuid,p_version uuid) returns void language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null or not coalesce(public.is_staff(),false) then raise exception '교직원만 확인할 수 있습니다.';end if;
 if not exists(select 1 from public.current_schedule_reminders() where source=p_source and source_id=p_id and version=p_version) then raise exception '변경되었거나 삭제된 알림입니다. 다시 확인해 주세요.';end if;
 update public.schedule_reminder_receipts set dismissed_at=coalesce(dismissed_at,now())
 where profile_id=auth.uid() and source=p_source and source_id=p_id and version=p_version and read_at is not null;
 if not found then raise exception '확인한 알림만 삭제할 수 있습니다.';end if;
 insert into public.staff_live_signals(key,topic,entity_id) values('reminders:'||auth.uid(),'reminders',auth.uid()) on conflict(key) do update set changed_at=clock_timestamp();
end $$;
revoke all on function public.staff_dismiss_schedule_reminder(text,uuid,uuid) from public,anon;
grant execute on function public.staff_dismiss_schedule_reminder(text,uuid,uuid) to authenticated;
