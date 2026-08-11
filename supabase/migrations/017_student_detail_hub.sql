-- 교직원이 학생의 수강·출결·보강·과제·상담·보호자 기록을 한 번에 조회합니다.

create or replace function public.staff_student_detail_hub(p_student_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 학생 통합 기록을 확인할 수 있습니다.'; end if;
  if not exists (select 1 from public.students where id = p_student_id) then raise exception '학생을 찾을 수 없습니다.'; end if;
  select jsonb_build_object(
    'summary', jsonb_build_object(
      'attendanceTotal', (select count(*) from public.attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=p_student_id and l.lesson_date>=current_date-90),
      'present', (select count(*) from public.attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=p_student_id and l.lesson_date>=current_date-90 and a.status='present'),
      'late', (select count(*) from public.attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=p_student_id and l.lesson_date>=current_date-90 and a.status='late'),
      'absent', (select count(*) from public.attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=p_student_id and l.lesson_date>=current_date-90 and a.status='absent'),
      'assignmentOpen', (select count(*) from public.assignments ass join public.enrollments e on e.class_id=ass.class_id and e.student_id=p_student_id and e.status='active' left join public.assignment_submissions sub on sub.assignment_id=ass.id and sub.student_id=p_student_id where coalesce(sub.status,'pending'::public.assignment_submission_status)<>'reviewed'),
      'upcomingMakeups', (select count(*) from public.makeup_sessions ms join public.attendance a on a.id=ms.attendance_id where a.student_id=p_student_id and ms.status='scheduled' and ms.scheduled_at>=now()),
      'lastConsultedAt', (select max(consulted_at) from public.consultations where student_id=p_student_id)
    ),
    'classes', coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'name',c.name,'subject',c.subject,'room',c.room,'status',e.status,'startedOn',e.started_on,'teachers',coalesce((select string_agg(p.display_name,' · ' order by p.display_name) from public.class_teachers ct join public.profiles p on p.id=ct.profile_id where ct.class_id=c.id),'')) order by (e.status='active') desc,e.started_on desc) from public.enrollments e join public.classes c on c.id=e.class_id where e.student_id=p_student_id),'[]'::jsonb),
    'guardians', coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'name',g.name,'phone',g.phone,'relationship',sg.relationship,'isPrimary',sg.is_primary) order by sg.is_primary desc,g.name) from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id where sg.student_id=p_student_id),'[]'::jsonb),
    'attendance', coalesce((select jsonb_agg(row_data order by lesson_date desc) from (select jsonb_build_object('id',a.id,'lessonDate',l.lesson_date,'className',c.name,'status',a.status,'note',a.note) row_data,l.lesson_date from public.attendance a join public.lessons l on l.id=a.lesson_id join public.classes c on c.id=l.class_id where a.student_id=p_student_id order by l.lesson_date desc limit 30) recent),'[]'::jsonb),
    'makeups', coalesce((select jsonb_agg(jsonb_build_object('id',ms.id,'className',c.name,'missedDate',l.lesson_date,'scheduledAt',ms.scheduled_at,'endsAt',ms.ends_at,'room',ms.room,'status',ms.status,'teacherName',p.display_name,'note',ms.note) order by ms.scheduled_at desc) from public.makeup_sessions ms join public.attendance a on a.id=ms.attendance_id join public.lessons l on l.id=a.lesson_id join public.classes c on c.id=l.class_id join public.profiles p on p.id=ms.teacher_profile_id where a.student_id=p_student_id),'[]'::jsonb),
    'assignments', coalesce((select jsonb_agg(row_data order by due_at desc) from (select jsonb_build_object('id',ass.id,'title',ass.title,'className',c.name,'dueAt',ass.due_at,'status',coalesce(sub.status,'pending'::public.assignment_submission_status),'feedback',sub.feedback) row_data,ass.due_at from public.assignments ass join public.classes c on c.id=ass.class_id left join public.assignment_submissions sub on sub.assignment_id=ass.id and sub.student_id=p_student_id where exists (select 1 from public.enrollments e where e.class_id=ass.class_id and e.student_id=p_student_id) order by ass.due_at desc limit 20) recent),'[]'::jsonb),
    'consultations', coalesce((select jsonb_agg(row_data order by consulted_at desc) from (select jsonb_build_object('id',con.id,'consultedAt',con.consulted_at,'type',con.consultation_type,'consultantName',coalesce(p.display_name,t.name,'담당 선생님'),'internalNote',con.internal_note,'nextContactOn',con.next_contact_on) row_data,con.consulted_at from public.consultations con left join public.profiles p on p.id=con.consultant_profile_id left join public.teachers t on t.id=con.teacher_id where con.student_id=p_student_id order by con.consulted_at desc limit 20) recent),'[]'::jsonb)
  ) into result;
  return result;
end
$$;

revoke all on function public.staff_student_detail_hub(uuid) from public;
grant execute on function public.staff_student_detail_hub(uuid) to authenticated;
