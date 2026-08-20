-- 차량 상세 팝업에서만 사용하는 학생별 특이사항

alter table public.students
add column if not exists vehicle_note text;

notify pgrst,'reload schema';
