-- 학부모/학생 성적 추이에서 정규·보강·추가·첨삭 시험을 과목/항목별로 구분한다.
-- 기존 테이블과 데이터는 변경하지 않고 조회 결과만 확장한다.
create or replace function public.family_exam_progress(p_student_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_role public.user_role; v_student_id uuid; v_result jsonb;
begin
  v_role:=public.current_user_role();
  if v_role not in ('student','guardian') then raise exception '학생 또는 학부모 계정만 시험 결과를 확인할 수 있습니다.'; end if;
  if v_role='student' then
    select s.id into v_student_id from public.students s where s.profile_id=auth.uid();
    if p_student_id is not null and p_student_id<>v_student_id then raise exception '본인의 시험 결과만 확인할 수 있습니다.'; end if;
  else
    select s.id into v_student_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id
    where g.profile_id=auth.uid() and (p_student_id is null or s.id=p_student_id) order by sg.is_primary desc,s.name limit 1;
    if p_student_id is not null and v_student_id is null then raise exception '연결된 자녀의 시험 결과만 확인할 수 있습니다.'; end if;
  end if;
  select coalesce(jsonb_agg(row_data order by lesson_date desc,created_at desc),'[]'::jsonb) into v_result from (
    select lesson_date,created_at,jsonb_build_object('id',id,'lessonDate',lesson_date,'className',class_name,'subject',subject_name,'mainSubject',main_subject,'examType',exam_type,'examTitle',exam_title,'itemType',item_type,'score',score,'maxScore',max_score,'percent',percent,'evaluation',evaluation,'feedback',feedback,'teacherName',teacher_name) row_data
    from (
      select r.id,r.created_at,l.lesson_date,c.name class_name,coalesce(subject.name,c.subject) subject_name,coalesce(subject.main_subject,c.subject) main_subject,
        coalesce(r.exam_type,'') exam_type,coalesce(r.exam_title,l.exam_content,'') exam_title,'regular'::text item_type,r.score,coalesce(nullif(r.max_score,0),100) max_score,
        case when r.score is null then null else round(r.score/coalesce(nullif(r.max_score,0),100)*100,1) end percent,coalesce(r.evaluation,'') evaluation,coalesce(r.feedback,'') feedback,coalesce(p.display_name,'담당 선생님') teacher_name
      from public.lesson_exam_results r join public.lessons l on l.id=r.lesson_id join public.classes c on c.id=l.class_id
      left join public.academy_subjects subject on subject.id=c.subject_id left join public.profiles p on p.id=coalesce(r.created_by,l.teacher_profile_id)
      where r.student_id=v_student_id and r.score is not null
      union all
      select r.id,r.updated_at,l.lesson_date,case when l.kind='makeup' then '개별 보강' else '추가수업' end,
        coalesce(subject.name,case when l.kind='makeup' then '보강' else '추가수업' end),coalesce(subject.main_subject,subject.name,''),coalesce(r.exam_type,''),coalesce(r.exam_title,''),
        case when l.kind='makeup' then 'makeup' else 'extra' end,r.score,coalesce(nullif(r.max_score,0),100),
        case when r.score is null then null else round(r.score/coalesce(nullif(r.max_score,0),100)*100,1) end,coalesce(r.evaluation,''),coalesce(r.evaluation,''),coalesce(p.display_name,'담당 선생님')
      from public.teacher_special_lesson_exam_results r join public.teacher_special_lessons l on l.id=r.session_id
      join public.teacher_special_lesson_students a on a.session_id=l.id and a.student_id=v_student_id
      left join public.academy_subjects subject on subject.id=l.subject_id left join public.profiles p on p.id=l.teacher_profile_id
      where r.student_id=v_student_id and l.status='completed' and r.score is not null
    ) all_exams order by lesson_date desc,created_at desc limit 120
  ) exam_rows;
  return v_result;
end $$;

create or replace function public.family_correction_exam_progress(p_student_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare role_now public.user_role; allowed_id uuid;
begin
  role_now:=public.current_user_role();
  if role_now='student' then select id into allowed_id from public.students where profile_id=auth.uid() and id=p_student_id;
  elsif role_now='guardian' then select s.id into allowed_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() and s.id=p_student_id; end if;
  if allowed_id is null then raise exception '연결된 학생의 첨삭 성적만 확인할 수 있습니다.'; end if;
  return coalesce((select jsonb_agg(to_jsonb(q) order by q."lessonDate" desc,q.id desc) from (
    select r.id,r.correction_date as "lessonDate",(r.subject||' 첨삭')::text as "className",r.subject,r.subject as "mainSubject",'첨삭 시험'::text as "examType",r.exam_title as "examTitle",'correction'::text as "itemType",r.exam_score as score,
      coalesce(nullif(r.exam_max_score,0),100) as "maxScore",case when r.exam_score is null then null else round(r.exam_score*100.0/coalesce(nullif(r.exam_max_score,0),100),1) end as percent
    from public.correction_reports r where r.student_id=allowed_id and r.published and r.exam_score is not null order by r.correction_date desc,r.created_at desc limit 80
  ) q),'[]'::jsonb);
end $$;
revoke all on function public.family_exam_progress(uuid),public.family_correction_exam_progress(uuid) from public,anon;
grant execute on function public.family_exam_progress(uuid),public.family_correction_exam_progress(uuid) to authenticated;
notify pgrst,'reload schema';
