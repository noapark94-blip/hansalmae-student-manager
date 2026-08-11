-- 학생과 학부모에게 역할별로 허용된 실제 학습 현황만 제공합니다.

create or replace function public.family_live_dashboard(p_student_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare viewer_role public.user_role; selected_id uuid; result jsonb;
begin
  viewer_role := public.current_user_role();
  if viewer_role is null or viewer_role not in ('student','guardian') then raise exception '학생 또는 학부모 계정만 가족 대시보드를 확인할 수 있습니다.'; end if;
  if viewer_role='student' then
    select id into selected_id from public.students where profile_id=auth.uid();
    if p_student_id is not null and p_student_id<>selected_id then raise exception '본인 학생 정보만 확인할 수 있습니다.'; end if;
  else
    if p_student_id is null then select s.id into selected_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() order by sg.is_primary desc,s.name limit 1;
    else
      select s.id into selected_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() and s.id=p_student_id;
      if selected_id is null then raise exception '연결된 자녀만 확인할 수 있습니다.'; end if;
    end if;
  end if;
  select jsonb_build_object(
    'role',viewer_role,
    'children',case when viewer_role='guardian' then coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade) order by sg.is_primary desc,s.name) from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid()),'[]'::jsonb) else coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade)) from public.students s where s.id=selected_id),'[]'::jsonb) end,
    'selectedStudent',(select jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade) from public.students s where s.id=selected_id),
    'weekClasses',coalesce((select jsonb_agg(jsonb_build_object('id',cs.id,'name',c.name,'subject',c.subject,'room',c.room,'color',c.color,'weekday',cs.weekday,'startTime',cs.start_time,'endTime',cs.end_time,'teachers',coalesce((select string_agg(p.display_name,' · ' order by p.display_name) from public.class_teachers ct join public.profiles p on p.id=ct.profile_id where ct.class_id=c.id),'')) order by cs.weekday,cs.start_time) from public.enrollments e join public.classes c on c.id=e.class_id join public.class_schedules cs on cs.class_id=c.id where e.student_id=selected_id and e.status='active' and c.active and (cs.valid_from is null or cs.valid_from<=current_date) and (cs.valid_until is null or cs.valid_until>=current_date)),'[]'::jsonb),
    'upcomingClasses',coalesce((select jsonb_agg(row_data order by class_date,start_time) from (select jsonb_build_object('id',cs.id,'name',c.name,'subject',c.subject,'room',c.room,'color',c.color,'classDate',days.class_date,'startTime',cs.start_time,'teachers',coalesce((select string_agg(p.display_name,' · ' order by p.display_name) from public.class_teachers ct join public.profiles p on p.id=ct.profile_id where ct.class_id=c.id),'')) row_data,days.class_date,cs.start_time from public.enrollments e join public.classes c on c.id=e.class_id join public.class_schedules cs on cs.class_id=c.id cross join lateral (select day::date class_date from generate_series(current_date,current_date+13,interval '1 day') day) days where e.student_id=selected_id and e.status='active' and c.active and cs.weekday=extract(isodow from days.class_date)::smallint and (cs.valid_from is null or cs.valid_from<=days.class_date) and (cs.valid_until is null or cs.valid_until>=days.class_date) and not exists(select 1 from public.schedule_exceptions se where se.class_id=c.id and se.original_date=days.class_date and se.kind='cancelled') order by days.class_date,cs.start_time limit 6) upcoming),'[]'::jsonb),
    'attendanceSummary',jsonb_build_object('total',(select count(*) from public.attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=selected_id and l.lesson_date>=date_trunc('month',current_date)::date),'present',(select count(*) from public.attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=selected_id and l.lesson_date>=date_trunc('month',current_date)::date and a.status='present'),'late',(select count(*) from public.attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=selected_id and l.lesson_date>=date_trunc('month',current_date)::date and a.status='late'),'absent',(select count(*) from public.attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=selected_id and l.lesson_date>=date_trunc('month',current_date)::date and a.status='absent')),
    'recentAttendance',coalesce((select jsonb_agg(row_data order by lesson_date desc) from (select jsonb_build_object('id',a.id,'lessonDate',l.lesson_date,'className',c.name,'status',a.status,'note',a.note) row_data,l.lesson_date from public.attendance a join public.lessons l on l.id=a.lesson_id join public.classes c on c.id=l.class_id where a.student_id=selected_id order by l.lesson_date desc limit 10) recent),'[]'::jsonb),
    'makeups',coalesce((select jsonb_agg(jsonb_build_object('id',ms.id,'className',c.name,'scheduledAt',ms.scheduled_at,'room',ms.room,'status',ms.status,'teacherName',p.display_name) order by ms.scheduled_at) from public.makeup_sessions ms join public.attendance a on a.id=ms.attendance_id join public.lessons l on l.id=a.lesson_id join public.classes c on c.id=l.class_id join public.profiles p on p.id=ms.teacher_profile_id where a.student_id=selected_id and ms.status<>'cancelled' and ms.scheduled_at>=now()-interval '30 days'),'[]'::jsonb),
    'assignments',coalesce((select jsonb_agg(row_data order by due_at) from (select jsonb_build_object('id',ass.id,'title',ass.title,'className',c.name,'dueAt',ass.due_at,'status',coalesce(sub.status,'pending'::public.assignment_submission_status),'feedback',sub.feedback) row_data,ass.due_at from public.assignments ass join public.classes c on c.id=ass.class_id left join public.assignment_submissions sub on sub.assignment_id=ass.id and sub.student_id=selected_id where exists(select 1 from public.enrollments e where e.class_id=ass.class_id and e.student_id=selected_id and e.status='active') order by (coalesce(sub.status,'pending'::public.assignment_submission_status)='reviewed'),ass.due_at limit 12) work),'[]'::jsonb),
    'announcements',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'title',a.title,'body',a.body,'publishedAt',a.published_at,'authorName',coalesce(p.display_name,'한살매')) order by a.published_at desc) from public.announcements a left join public.profiles p on p.id=a.author_profile_id where a.published_at is not null and a.published_at<=now() and (a.expires_at is null or a.expires_at>now()) and (a.audience='all' or (a.audience='student' and a.student_id=selected_id) or (a.audience='class' and exists(select 1 from public.enrollments e where e.student_id=selected_id and e.class_id=a.class_id and e.status='active'))) limit 10),'[]'::jsonb),
    'consultations',coalesce((select jsonb_agg(jsonb_build_object('id',con.id,'consultedAt',con.consulted_at,'type',con.consultation_type,'consultantName',coalesce(p.display_name,t.name,'담당 선생님'),'summary',case when viewer_role='student' then con.student_summary else con.guardian_summary end,'nextContactOn',con.next_contact_on) order by con.consulted_at desc) from public.consultations con left join public.profiles p on p.id=con.consultant_profile_id left join public.teachers t on t.id=con.teacher_id where con.student_id=selected_id and (case when viewer_role='student' then con.student_summary else con.guardian_summary end) is not null limit 10),'[]'::jsonb)
  ) into result;
  return result;
end
$$;

revoke all on function public.family_live_dashboard(uuid) from public;
grant execute on function public.family_live_dashboard(uuid) to authenticated;
