-- 로그인 전용 데일리·위클리 학습 리포트 발행과 열람 확인

create table public.learning_report_publications (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  report_type text not null check (report_type in ('daily','weekly')),
  period_start date not null,
  period_end date not null,
  teacher_comment text,
  snapshot jsonb not null default '[]'::jsonb,
  status text not null default 'draft' check (status in ('draft','published')),
  created_by uuid not null references public.profiles(id) on delete restrict,
  updated_by uuid not null references public.profiles(id) on delete restrict,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (student_id, report_type, period_start),
  check (period_end >= period_start),
  check (jsonb_typeof(snapshot) = 'array')
);

create index learning_report_publications_family_idx
  on public.learning_report_publications(student_id, status, period_start desc);

create table public.learning_report_publication_reads (
  publication_id uuid not null references public.learning_report_publications(id) on delete cascade,
  viewer_profile_id uuid not null references public.profiles(id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (publication_id, viewer_profile_id)
);

alter table public.learning_report_publications enable row level security;
alter table public.learning_report_publication_reads enable row level security;

create policy learning_report_staff_rows on public.learning_report_publications
for all to authenticated using (public.is_staff()) with check (public.is_staff());
create policy learning_report_reads_own on public.learning_report_publication_reads
for select to authenticated using (viewer_profile_id = auth.uid());

grant select, insert, update, delete on public.learning_report_publications to authenticated;
grant select on public.learning_report_publication_reads to authenticated;

create or replace function public.can_staff_report_student(p_student_id uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.current_user_role()='admin' or (
    public.current_user_role()='teacher' and (
      exists(select 1 from public.enrollments e join public.class_teachers ct on ct.class_id=e.class_id where e.student_id=p_student_id and ct.profile_id=auth.uid())
      or exists(select 1 from public.teacher_special_lesson_students a join public.teacher_special_lessons l on l.id=a.session_id where a.student_id=p_student_id and l.teacher_profile_id=auth.uid())
      or exists(select 1 from public.correction_assignments ca where ca.student_id=p_student_id and ca.teacher_profile_id=auth.uid())
    )
  )
$$;

create or replace function public.staff_learning_report_source(p_student_id uuid,p_from date,p_to date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare base_rows jsonb; result jsonb;
begin
  if p_from is null or p_to is null or p_to<p_from or p_to-p_from>31 then raise exception '조회 기간을 확인해 주세요.'; end if;
  if not public.can_staff_report_student(p_student_id) then raise exception '담당 학생의 리포트만 만들 수 있습니다.'; end if;
  base_rows:=public.staff_student_completed_learning_history(p_student_id,500);
  select coalesce(jsonb_agg(item order by report_date,starts_at),'[]'::jsonb) into result from (
    select jsonb_set(entry.item,'{source}',to_jsonb(case
      when entry.item->>'source' in ('makeup','extra') then entry.item->>'source'
      when exists(select 1 from public.class_makeup_attendees ma where ma.class_id=(entry.item->>'classId')::uuid and ma.student_id=p_student_id and ma.attendance_date=(entry.item->>'lessonDate')::date) then 'makeup'
      else 'regular' end)) item,
      (entry.item->>'lessonDate')::date report_date,entry.item->>'startsAt' starts_at
    from jsonb_array_elements(coalesce(base_rows,'[]'::jsonb)) entry(item)
    where (entry.item->>'lessonDate')::date between p_from and p_to
    union all
    select jsonb_build_object(
      'lessonId',r.id,'lessonDate',to_char(r.correction_date,'YYYY-MM-DD'),
      'startsAt',to_char(r.correction_date,'YYYY-MM-DD')||'T'||r.start_time::text||'+09:00',
      'classId',r.assignment_id,'className','첨삭','subject',r.subject,'source','correction','room',null,
      'teacherName',coalesce(r.recorded_by_name,'담당 선생님'),'lessonContent',coalesce(r.correction_content,''),
      'homeworkContent',coalesce(r.next_preparation,r.homework_instruction,''),'examContent',coalesce(r.exam_range,''),
      'attendance',jsonb_build_object('status',r.attendance_status,'lateMinutes',r.late_minutes,'absenceReason','','note',coalesce(r.assistant_feedback,'')),
      'homeworkResult',case when r.homework_status is null then null else jsonb_build_object('status',r.homework_status,'note',coalesce(r.homework_note,'')) end,
      'exams',case when r.exam_title is null and r.exam_score is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object(
        'id',r.id,'examType','첨삭 평가','examTitle',coalesce(r.exam_title,''),'score',r.exam_score,'maxScore',coalesce(r.exam_max_score,100),
        'percent',case when r.exam_score is null or coalesce(r.exam_max_score,0)<=0 then null else round(r.exam_score/r.exam_max_score*100,1) end,
        'evaluation',coalesce(r.evaluation,''),'feedback',coalesce(r.teacher_instruction,''))) end
    ) item,r.correction_date report_date,r.start_time::text starts_at
    from public.correction_reports r join public.correction_assignments ca on ca.id=r.assignment_id
    where r.student_id=p_student_id and r.correction_date between p_from and p_to and r.published
      and (public.current_user_role()='admin' or ca.teacher_profile_id=auth.uid())
  ) rows;
  return result;
end $$;

create or replace function public.staff_save_learning_report(
  p_student_id uuid,p_report_type text,p_period_start date,p_period_end date,
  p_teacher_comment text,p_snapshot jsonb,p_publish boolean default false
) returns uuid language plpgsql security definer set search_path=public as $$
declare rid uuid;
begin
  if p_report_type not in ('daily','weekly') or p_period_end<p_period_start or jsonb_typeof(coalesce(p_snapshot,'[]'::jsonb))<>'array' then raise exception '리포트 내용을 확인해 주세요.'; end if;
  if not public.can_staff_report_student(p_student_id) then raise exception '담당 학생의 리포트만 저장할 수 있습니다.'; end if;
  insert into public.learning_report_publications(student_id,report_type,period_start,period_end,teacher_comment,snapshot,status,created_by,updated_by,published_at)
  values(p_student_id,p_report_type,p_period_start,p_period_end,nullif(trim(p_teacher_comment),''),coalesce(p_snapshot,'[]'::jsonb),case when p_publish then 'published' else 'draft' end,auth.uid(),auth.uid(),case when p_publish then now() else null end)
  on conflict(student_id,report_type,period_start) do update set
    period_end=excluded.period_end,teacher_comment=excluded.teacher_comment,snapshot=excluded.snapshot,status=excluded.status,
    updated_by=auth.uid(),updated_at=now(),published_at=case when p_publish then coalesce(public.learning_report_publications.published_at,now()) else null end
  returning id into rid;
  return rid;
end $$;

create or replace function public.learning_report_list()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare role_now public.user_role;
begin
  role_now:=public.current_user_role();
  if role_now is null then raise exception '로그인이 필요합니다.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id',p.id,'studentId',s.id,'studentName',s.name,'reportType',p.report_type,'periodStart',p.period_start,'periodEnd',p.period_end,
    'status',p.status,'publishedAt',p.published_at,'viewedAt',(select max(r.viewed_at) from public.learning_report_publication_reads r where r.publication_id=p.id)
  ) order by p.period_start desc,s.name) from public.learning_report_publications p join public.students s on s.id=p.student_id
  where (role_now in ('admin','teacher') and public.can_staff_report_student(s.id))
    or (p.status='published' and ((role_now='student' and s.profile_id=auth.uid()) or (role_now='guardian' and exists(
      select 1 from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id where sg.student_id=s.id and g.profile_id=auth.uid()
    ))))),'[]'::jsonb);
end $$;

create or replace function public.learning_report_detail(p_publication_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare role_now public.user_role; result jsonb;
begin
  role_now:=public.current_user_role();
  select jsonb_build_object('id',p.id,'studentId',s.id,'studentName',s.name,'school',coalesce(s.school,''),'grade',coalesce(s.grade,''),
    'reportType',p.report_type,'periodStart',p.period_start,'periodEnd',p.period_end,'teacherComment',coalesce(p.teacher_comment,''),
    'snapshot',p.snapshot,'status',p.status,'publishedAt',p.published_at,'viewedAt',(select r.viewed_at from public.learning_report_publication_reads r where r.publication_id=p.id and r.viewer_profile_id=auth.uid()))
  into result from public.learning_report_publications p join public.students s on s.id=p.student_id where p.id=p_publication_id and (
    (role_now in ('admin','teacher') and public.can_staff_report_student(s.id))
    or (p.status='published' and ((role_now='student' and s.profile_id=auth.uid()) or (role_now='guardian' and exists(
      select 1 from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id where sg.student_id=s.id and g.profile_id=auth.uid()
    )))));
  if result is null then raise exception '확인할 수 없는 리포트입니다.'; end if;
  return result;
end $$;

create or replace function public.mark_learning_report_read(p_publication_id uuid)
returns timestamptz language plpgsql security definer set search_path=public as $$
declare role_now public.user_role; ts timestamptz:=now();
begin
  role_now:=public.current_user_role();
  if role_now not in ('student','guardian') or not exists(
    select 1 from public.learning_report_publications p join public.students s on s.id=p.student_id where p.id=p_publication_id and p.status='published' and
    ((role_now='student' and s.profile_id=auth.uid()) or (role_now='guardian' and exists(select 1 from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id where sg.student_id=s.id and g.profile_id=auth.uid())))
  ) then raise exception '확인할 수 없는 리포트입니다.'; end if;
  insert into public.learning_report_publication_reads(publication_id,viewer_profile_id,viewed_at) values(p_publication_id,auth.uid(),ts)
  on conflict(publication_id,viewer_profile_id) do update set viewed_at=excluded.viewed_at;
  return ts;
end $$;

revoke all on function public.can_staff_report_student(uuid),public.staff_learning_report_source(uuid,date,date),public.staff_save_learning_report(uuid,text,date,date,text,jsonb,boolean),public.learning_report_list(),public.learning_report_detail(uuid),public.mark_learning_report_read(uuid) from public,anon;
grant execute on function public.staff_learning_report_source(uuid,date,date),public.staff_save_learning_report(uuid,text,date,date,text,jsonb,boolean),public.learning_report_list(),public.learning_report_detail(uuid),public.mark_learning_report_read(uuid) to authenticated;
notify pgrst,'reload schema';
