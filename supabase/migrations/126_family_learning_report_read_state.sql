-- 가족 계정의 NEW 표시는 다른 가족이 아닌 현재 로그인 사용자의 열람만 반영합니다.

create or replace function public.learning_report_list()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare role_now public.user_role;
begin
  role_now:=public.current_user_role();
  if role_now is null then raise exception '로그인이 필요합니다.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',p.id,'studentId',s.id,'studentName',s.name,'reportType',p.report_type,'periodStart',p.period_start,'periodEnd',p.period_end,
    'status',p.status,'publishedAt',p.published_at,'viewedAt',(select max(r.viewed_at) from public.learning_report_publication_reads r
      where r.publication_id=p.id and (role_now in ('admin','teacher') or r.viewer_profile_id=auth.uid()))
  ) order by p.period_start desc,s.name) from public.learning_report_publications p join public.students s on s.id=p.student_id
  where (role_now in ('admin','teacher') and public.can_staff_report_student(s.id))
    or (p.status='published' and ((role_now='student' and s.profile_id=auth.uid()) or (role_now='guardian' and exists(
      select 1 from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id where sg.student_id=s.id and g.profile_id=auth.uid()
    ))))),'[]'::jsonb);
end $$;

revoke all on function public.learning_report_list() from public,anon;
grant execute on function public.learning_report_list() to authenticated;
notify pgrst,'reload schema';
