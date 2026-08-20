-- 기존 교직원 RLS 범위 안에서 차량 상세 팝업의 보호자 정보 수정을 허용합니다.

grant select (id, name, phone) on public.guardians to authenticated;
grant update (name, phone) on public.guardians to authenticated;
grant select (student_id, guardian_id, is_primary) on public.student_guardians to authenticated;

notify pgrst,'reload schema';
