-- 로그인 사용자가 RLS 정책을 통과한 행을 조회할 수 있도록 기본 권한을 부여합니다.
-- 실제 접근 범위는 002_auth_and_role_policies.sql의 역할별 RLS가 계속 제한합니다.

grant usage on schema public to authenticated;

grant select on table
  public.profiles,
  public.students,
  public.enrollments,
  public.classes
to authenticated;
