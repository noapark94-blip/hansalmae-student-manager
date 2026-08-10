-- 실제 행 쓰기 가능 여부는 002의 staff_manage_students RLS 정책이 제한합니다.
grant insert, update, delete on table public.students to authenticated;
