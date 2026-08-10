-- 실제 행 쓰기 가능 여부는 002의 staff_manage_classes 및 staff_manage_enrollments RLS가 제한합니다.
grant insert, update, delete on table public.classes, public.enrollments to authenticated;
