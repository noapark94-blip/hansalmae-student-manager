-- Run inside an explicit transaction and always ROLLBACK. Uses actual existing RPCs.
do $test$
declare a public.correction_assignments; aid uuid; teacher uuid; base jsonb; r jsonb; next_id uuid; latest jsonb;
 e_id uuid; e_base jsonb; denied boolean; assistant uuid; unchanged bigint; d date:=current_date+30;
begin
 select id into aid from public.profiles where role='admin' and is_active limit 1;
 perform set_config('request.jwt.claim.sub',aid::text,true);
 select ca.* into a from public.correction_assignments ca join public.students s on s.id=ca.student_id
 join public.profiles p on p.id=ca.teacher_profile_id and p.is_active
 where ca.active and ca.subject is not null and ca.valid_from<(timezone('Asia/Seoul',now()))::date and s.status in ('active','재원')
 and exists(select 1 from public.correction_reports cr where cr.assignment_id=ca.id and (cr.published or cr.attendance_status<>'scheduled'))
 and not exists(select 1 from public.correction_schedule_exceptions x where x.assignment_id=ca.id and x.target_date>=current_date)
 limit 1;
 if a.id is null then raise exception 'No valid rollback-test target'; end if;
 select id into teacher from public.profiles where is_active and role::text in ('admin','teacher','sub_admin') and id is distinct from a.tutor_profile_id limit 1;
 base:=public.correction_assignment_edit_values(a);
 r:=public.staff_patch_correction_assignment(a.id,base,jsonb_build_object('tutorId',teacher::text),false);
 if not coalesce((r->>'saved')::boolean,false) then raise exception 'Tutor save failed'; end if;
 next_id:=(r->>'id')::uuid;
 if next_id=a.id then raise exception 'History replacement was not exercised'; end if;
 r:=public.staff_patch_correction_assignment(a.id,base,'{"note":"rollback concurrency test"}',false);
 if r#>>'{values,tutorId}'<>teacher::text or r#>>'{values,note}'<>'rollback concurrency test' then raise exception 'Disjoint edit lost'; end if;
 latest:=r->'values';
 r:=public.staff_patch_correction_assignment(a.id,base,'{"note":"conflicting note"}',false);
 if not(r->'conflicts'?'note') then raise exception 'Same-field conflict not caught'; end if;
 r:=public.staff_patch_correction_assignment(a.id,base,'{}',true);
 if not(r?'conflicts') then raise exception 'Stale delete accepted'; end if;
 -- A stale fixed schedule cannot be used to create an exception.
 denied:=false;
 begin perform public.staff_add_guarded_correction_exception(a.id,base,d,'cancel',null,null,null,'test');
 exception when others then if sqlerrm not like '%삭제되거나%' then raise; end if;denied:=true;end;
 if not denied then raise exception 'Stale exception accepted'; end if;
 e_id:=public.staff_add_guarded_correction_exception(next_id,latest,d,'cancel',null,null,null,'test');
 e_base:=jsonb_build_object('assignmentId',next_id,'originalDate',d,'kind','cancel','targetDate',null,'targetStartTime',null,'targetEndTime',null,'note','test');
 denied:=false;
 begin perform public.staff_delete_guarded_correction_exception(e_id,e_base||'{"note":"stale"}');
 exception when others then if sqlerrm not like '%다른 담당자%' then raise; end if;denied:=true;end;
 if not denied then raise exception 'Stale exception deletion accepted'; end if;
 perform public.staff_delete_guarded_correction_exception(e_id,e_base);
 if exists(select 1 from public.correction_schedule_exceptions where id=e_id) then raise exception 'Exception deletion failed'; end if;
 r:=public.staff_patch_correction_assignment(a.id,latest,'{}',true);
 if not coalesce((r->>'saved')::boolean,false) then raise exception 'Guarded deletion failed'; end if;
 r:=public.staff_patch_correction_assignment(a.id,latest,'{"note":"must not revive"}',false);
 if not coalesce((r->>'deleted')::boolean,false) then raise exception 'Deleted assignment revived'; end if;
 select id into assistant from public.profiles where is_active and role::text='assistant' limit 1;
 if assistant is null then raise exception 'No assistant for rollback test'; end if;
 select count(*) into unchanged from public.correction_slot_assistants where not(assistant_profile_id=assistant and weekday in (1,2) and start_time='14:30');
 perform public.staff_patch_correction_slot_assistants(jsonb_build_array(jsonb_build_object('weekday',1,'startTime','14:30','assistantId',assistant,'selected',true)));
 perform public.staff_patch_correction_slot_assistants(jsonb_build_array(jsonb_build_object('weekday',2,'startTime','14:30','assistantId',assistant,'selected',true)));
 if (select count(*) from public.correction_slot_assistants where assistant_profile_id=assistant and weekday in (1,2) and start_time='14:30')<>2 then raise exception 'Assistant patch lost other slot'; end if;
 if (select count(*) from public.correction_slot_assistants where not(assistant_profile_id=assistant and weekday in (1,2) and start_time='14:30'))<>unchanged then raise exception 'Other memberships changed'; end if;
 perform set_config('request.jwt.claim.sub','',true);denied:=false;
 begin perform public.staff_patch_correction_assignment(a.id,base,'{}',false);
 exception when others then if sqlerrm not like '%교직원%' then raise; end if;denied:=true;end;
 if not denied then raise exception 'Unauthenticated update accepted'; end if;
end $test$;
