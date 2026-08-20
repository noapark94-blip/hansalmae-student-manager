-- RLS 정책 평가에 필요한 보호자 연결정보 읽기 권한

grant select on public.guardians to authenticated;
grant select on public.student_guardians to authenticated;

notify pgrst,'reload schema';
