create or replace function public.staff_patch_correction_slot_assistants(p_changes jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare item jsonb; d smallint; t time; a uuid;
begin
 if auth.uid() is null or coalesce(public.current_user_role() not in ('admin','sub_admin','teacher','assistant'),true) then raise exception '담당 조교를 수정할 권한이 없습니다.'; end if;
 if jsonb_typeof(p_changes) is distinct from 'array' then raise exception '담당 조교 배정을 확인해 주세요.'; end if;
 -- Serialize the small membership patch, without reading or replacing all slots.
 perform pg_advisory_xact_lock(hashtextextended('correction-slot-assistants',0));
 for item in select value from jsonb_array_elements(p_changes) loop
  d:=(item->>'weekday')::smallint;t:=(item->>'startTime')::time;a:=(item->>'assistantId')::uuid;
  if d is null or t is null or a is null or jsonb_typeof(item->'selected') is distinct from 'boolean' then raise exception '담당 조교 배정을 확인해 주세요.'; end if;
  if not((d between 1 and 5 and t in ('14:30'::time,'16:00'::time,'17:30'::time,'19:00'::time,'20:30'::time)) or
   (d between 6 and 7 and t in ('09:30'::time,'11:00'::time,'12:30'::time,'14:00'::time,'15:30'::time))) then raise exception '첨삭 시간대를 확인해 주세요.'; end if;
  if (item->>'selected')::boolean then
   if not exists(select 1 from public.profiles where id=a and is_active and role::text='assistant') then raise exception '활성 조교 계정만 배정할 수 있습니다.'; end if;
   insert into public.correction_slot_assistants(weekday,start_time,assistant_profile_id,created_by) values(d,t,a,auth.uid()) on conflict(weekday,start_time,assistant_profile_id) do nothing;
  else delete from public.correction_slot_assistants where weekday=d and start_time=t and assistant_profile_id=a;
  end if;
 end loop;
end $$;
revoke all on function public.staff_patch_correction_slot_assistants(jsonb) from public,anon;
grant execute on function public.staff_patch_correction_slot_assistants(jsonb) to authenticated;
