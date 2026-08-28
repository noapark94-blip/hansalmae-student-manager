-- 충돌 검사 내부 함수는 API에서 직접 호출하지 못하고 트리거에서만 사용합니다.
revoke all on function public.correction_time_start(time,smallint) from public,anon,authenticated;
revoke all on function public.correction_time_end(time,smallint) from public,anon,authenticated;
revoke all on function public.assert_class_student_schedule_available(uuid,uuid,smallint,time,time) from public,anon,authenticated;
revoke all on function public.prevent_class_schedule_conflict() from public,anon,authenticated;
revoke all on function public.prevent_correction_conflict() from public,anon,authenticated;
revoke all on function public.prevent_correction_schedule_exception_conflict() from public,anon,authenticated;
revoke all on function public.prevent_legacy_correction_exception_student_conflict() from public,anon,authenticated;
