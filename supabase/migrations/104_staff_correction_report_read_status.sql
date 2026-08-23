-- 교직원 첨삭 기록 화면에서 날짜별 학부모 리포트 확인 현황을 조회합니다.
create or replace function public.staff_correction_report_read_status(p_date date)
returns jsonb language sql stable security definer set search_path=public as $$
with published as (
  select r.id report_id,r.student_id from public.correction_reports r where r.correction_date=p_date and r.published
), students_for_date as (
  select distinct p.student_id,s.name student_name,s.school,s.grade from published p join public.students s on s.id=p.student_id
), status_rows as (
  select sfd.*,
    (select count(distinct g.profile_id)::integer from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id where sg.student_id=sfd.student_id and g.profile_id is not null) guardian_count,
    (select count(*)::integer from published p where p.student_id=sfd.student_id) report_count,
    (select count(distinct p.report_id)::integer from published p join public.correction_report_reads rr on rr.report_id=p.report_id and rr.student_id=sfd.student_id join public.guardians g on g.profile_id=rr.viewer_profile_id join public.student_guardians sg on sg.guardian_id=g.id and sg.student_id=sfd.student_id where p.student_id=sfd.student_id) read_report_count,
    (select max(rr.viewed_at) from published p join public.correction_report_reads rr on rr.report_id=p.report_id and rr.student_id=sfd.student_id join public.guardians g on g.profile_id=rr.viewer_profile_id join public.student_guardians sg on sg.guardian_id=g.id and sg.student_id=sfd.student_id where p.student_id=sfd.student_id) viewed_at
  from students_for_date sfd
), normalized as (
  select *,case when guardian_count=0 then 'unlinked' when read_report_count>=report_count then 'confirmed' else 'unconfirmed' end status from status_rows
)
select case when public.is_staff() then jsonb_build_object(
  'reportAvailable',exists(select 1 from published),'totalStudents',(select count(*) from normalized),
  'linkedStudents',(select count(*) from normalized where guardian_count>0),'confirmedStudents',(select count(*) from normalized where status='confirmed'),
  'unconfirmedStudents',(select count(*) from normalized where status='unconfirmed'),'unlinkedStudents',(select count(*) from normalized where status='unlinked'),
  'students',coalesce((select jsonb_agg(jsonb_build_object('studentId',student_id,'studentName',student_name,'school',school,'grade',grade,'guardianCount',guardian_count,'readCount',read_report_count,'status',status,'viewedAt',viewed_at) order by student_name) from normalized),'[]'::jsonb)
) else null end;
$$;
revoke all on function public.staff_correction_report_read_status(date) from public;
grant execute on function public.staff_correction_report_read_status(date) to authenticated;
notify pgrst,'reload schema';
