-- 학부모/학생 페이지: 첨삭 시험 성적 추이 전용 조회
create or replace function public.family_correction_exam_progress(p_student_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare role_now public.user_role; allowed_id uuid;
begin
  role_now:=public.current_user_role();
  if role_now='student' then
    select id into allowed_id from public.students where profile_id=auth.uid() and id=p_student_id;
  elsif role_now='guardian' then
    select s.id into allowed_id
    from public.guardians g
    join public.student_guardians sg on sg.guardian_id=g.id
    join public.students s on s.id=sg.student_id
    where g.profile_id=auth.uid() and s.id=p_student_id;
  end if;
  if allowed_id is null then raise exception '연결된 학생의 첨삭 성적만 확인할 수 있습니다.'; end if;
  return coalesce((select jsonb_agg(to_jsonb(q) order by q."lessonDate" desc,q.id desc) from (
    select r.id,r.correction_date as "lessonDate",(r.subject||' 첨삭')::text as "className",r.subject,r.exam_title as "examTitle",r.exam_score as score,
      coalesce(nullif(r.exam_max_score,0),100) as "maxScore",
      case when r.exam_score is null then null else round(r.exam_score*100.0/coalesce(nullif(r.exam_max_score,0),100),1) end as percent
    from public.correction_reports r
    where r.student_id=allowed_id and r.published and r.exam_score is not null
    order by r.correction_date desc,r.created_at desc limit 50
  ) q),'[]'::jsonb);
end $$;
revoke all on function public.family_correction_exam_progress(uuid) from public;
grant execute on function public.family_correction_exam_progress(uuid) to authenticated;
notify pgrst,'reload schema';
