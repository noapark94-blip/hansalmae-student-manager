-- Keep history-created replacement assignments connected for stale editors.
create table public.correction_assignment_successors (
 prior_id uuid primary key, next_id uuid not null,
 created_at timestamptz not null default now(), check(prior_id<>next_id)
);
alter table public.correction_assignment_successors enable row level security;
revoke all on public.correction_assignment_successors from public,anon,authenticated;

create function public.correction_assignment_edit_values(p_row public.correction_assignments)
returns jsonb language sql immutable set search_path=public as $$
 select jsonb_build_object('studentId',p_row.student_id,'subject',p_row.subject,
 'schedule',jsonb_build_object('weekday',p_row.weekday,'startTime',to_char(p_row.start_time,'HH24:MI'),'endTime',to_char(p_row.end_time,'HH24:MI')),
 'tutorId',coalesce(p_row.tutor_profile_id::text,''),'supervisorId',coalesce(p_row.supervisor_profile_id::text,''),'note',coalesce(p_row.note,''));
$$;
revoke all on function public.correction_assignment_edit_values(public.correction_assignments) from public,anon,authenticated;

create function public.staff_patch_correction_assignment(p_id uuid,p_base jsonb,p_changes jsonb,p_delete boolean default false)
returns jsonb language plpgsql security definer set search_path=public as $$
declare a public.correction_assignments; current_id uuid:=p_id; next_id uuid; result_id uuid; n int:=0;
 current_values jsonb; merged jsonb; conflict_keys jsonb; k text;
begin
 if auth.uid() is null or not public.is_staff() then raise exception '교직원만 첨삭 배정을 수정할 수 있습니다.'; end if;
 if jsonb_typeof(p_base) is distinct from 'object' or jsonb_typeof(p_changes) is distinct from 'object' then raise exception '수정 내용을 확인해 주세요.'; end if;
 -- Row locks serialize updates and deletes, including replacements made for history preservation.
 loop
  select * into a from public.correction_assignments where id=current_id for update;
  select s.next_id into next_id from public.correction_assignment_successors s where s.prior_id=current_id;
  exit when next_id is null;
  current_id:=next_id;n:=n+1;
  if n>50 then raise exception '최신 배정을 다시 열어 주세요.'; end if;
 end loop;
 if a.id is null or not a.active then return jsonb_build_object('deleted',true); end if;
 current_values:=public.correction_assignment_edit_values(a);
 for k in select jsonb_object_keys(p_changes) loop
  if not(current_values?k) or not(p_base?k) then raise exception '지원하지 않는 수정 항목입니다.'; end if;
 end loop;
 select coalesce(jsonb_agg(key),'[]') into conflict_keys from jsonb_object_keys(case when p_delete then current_values else p_changes end) key
 where (p_delete and (current_values->key is distinct from p_base->key))
 or (not p_delete and current_values->key is distinct from p_base->key and current_values->key is distinct from p_changes->key);
 if jsonb_array_length(conflict_keys)>0 then return jsonb_build_object('conflicts',conflict_keys,'id',a.id,'values',current_values); end if;
 if p_delete then
  perform public.staff_delete_correction_assignment(a.id);
  return jsonb_build_object('deleted',true,'saved',true);
 end if;
 merged:=current_values||p_changes;
 if merged=current_values then return jsonb_build_object('saved',true,'id',a.id,'values',current_values); end if;
 result_id:=public.staff_save_correction_assignment(a.id,(merged->>'studentId')::uuid,merged->>'subject',(merged#>>'{schedule,weekday}')::smallint,
 (merged#>>'{schedule,startTime}')::time,(merged#>>'{schedule,endTime}')::time,nullif(merged->>'tutorId','')::uuid,nullif(merged->>'supervisorId','')::uuid,merged->>'note');
 if result_id<>a.id then insert into public.correction_assignment_successors(prior_id,next_id) values(a.id,result_id); end if;
 select * into a from public.correction_assignments where id=result_id;
 return jsonb_build_object('saved',true,'id',result_id,'values',public.correction_assignment_edit_values(a));
end $$;
revoke all on function public.staff_patch_correction_assignment(uuid,jsonb,jsonb,boolean) from public,anon;
grant execute on function public.staff_patch_correction_assignment(uuid,jsonb,jsonb,boolean) to authenticated;

-- Patch membership by assistant/slot; never replace the entire weekly table.
create function public.staff_patch_correction_slot_assistants(p_changes jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare item jsonb; d smallint; t time; a uuid;
begin
 if auth.uid() is null or public.current_user_role() not in ('admin','sub_admin','teacher','assistant') then raise exception '담당 조교를 수정할 권한이 없습니다.'; end if;
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

create function public.staff_add_guarded_correction_exception(p_assignment_id uuid,p_base jsonb,p_original_date date,p_kind text,p_target_date date,p_target_start_time time,p_target_end_time time,p_note text)
returns uuid language plpgsql security definer set search_path=public as $$
declare a public.correction_assignments;
begin
 if auth.uid() is null or not public.is_staff() then raise exception '교직원만 일정을 변경할 수 있습니다.'; end if;
 select * into a from public.correction_assignments where id=p_assignment_id for update;
 if a.id is null or not a.active then raise exception '고정 배정이 삭제되거나 새 일정으로 변경됐습니다. 시간표에서 다시 열어 주세요.'; end if;
 if public.correction_assignment_edit_values(a) is distinct from p_base then raise exception '다른 담당자가 고정 배정을 수정했습니다. 시간표에서 최신 일정을 다시 확인해 주세요.'; end if;
 if p_kind in ('move','cancel') and exists(select 1 from public.correction_schedule_exceptions where assignment_id=p_assignment_id and original_date=p_original_date and kind in ('move','cancel')) then
  raise exception '다른 변경·취소 일정이 이미 있습니다. 최신 일정을 확인해 주세요.';
 end if;
 return public.staff_save_correction_exception(null,p_assignment_id,p_original_date,p_kind,p_target_date,p_target_start_time,p_target_end_time,p_note);
end $$;
revoke all on function public.staff_add_guarded_correction_exception(uuid,jsonb,date,text,date,time,time,text) from public,anon;
grant execute on function public.staff_add_guarded_correction_exception(uuid,jsonb,date,text,date,time,time,text) to authenticated;

create function public.staff_delete_guarded_correction_exception(p_id uuid,p_base jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare e public.correction_schedule_exceptions; v jsonb;
begin
 if auth.uid() is null or not public.is_staff() then raise exception '교직원만 일정 변경을 삭제할 수 있습니다.'; end if;
 select * into e from public.correction_schedule_exceptions where id=p_id for update;
 if e.id is null then return; end if;
 v:=jsonb_build_object('assignmentId',e.assignment_id,'originalDate',e.original_date,'kind',e.kind,'targetDate',e.target_date,
 'targetStartTime',to_char(e.target_start_time,'HH24:MI'),'targetEndTime',to_char(e.target_end_time,'HH24:MI'),'note',coalesce(e.note,''));
 if v is distinct from p_base then raise exception '다른 담당자가 일정을 수정했습니다. 최신 내용을 확인한 뒤 다시 취소해 주세요.'; end if;
 perform public.staff_delete_correction_exception(p_id);
end $$;
revoke all on function public.staff_delete_guarded_correction_exception(uuid,jsonb) from public,anon;
grant execute on function public.staff_delete_guarded_correction_exception(uuid,jsonb) to authenticated;
