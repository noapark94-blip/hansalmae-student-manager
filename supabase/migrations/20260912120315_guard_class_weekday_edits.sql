create or replace function public.staff_class_weekday_snapshot(p_class_id uuid,p_student_id uuid) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare choices jsonb;
begin
choices:=public.staff_class_student_schedule_choices(p_class_id,p_student_id);
return jsonb_build_object('choices',choices,'base',jsonb_build_object('assignments',public.student_assignment_version(p_student_id),'choices',choices));
end $$;
create or replace function public.staff_guard_class_weekdays(p_class_id uuid,p_student_id uuid,p_schedule_ids uuid[],p_base jsonb) returns void language plpgsql security definer set search_path=public as $$
declare snap jsonb;
begin
perform pg_advisory_xact_lock(hashtextextended('student_schedule:'||p_student_id::text,0));
snap:=public.staff_class_weekday_snapshot(p_class_id,p_student_id);
if p_base is distinct from snap->'base' then raise exception '수강 요일 또는 시간표가 변경됐습니다. 선택한 요일을 확인하고 창을 다시 열어 주세요.'; end if;
perform public.staff_save_class_student_schedule_assignments(p_class_id,p_student_id,p_schedule_ids);
end $$;
revoke all on function public.staff_class_weekday_snapshot(uuid,uuid),public.staff_guard_class_weekdays(uuid,uuid,uuid[],jsonb) from public,anon;
grant execute on function public.staff_class_weekday_snapshot(uuid,uuid),public.staff_guard_class_weekdays(uuid,uuid,uuid[],jsonb) to authenticated;