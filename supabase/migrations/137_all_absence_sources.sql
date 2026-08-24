-- 모든 수업 종류의 결석을 통합하고 첨삭·개별·추가수업 결석에도 보강 예약을 연결합니다.
create table if not exists public.source_makeup_sessions (
  id uuid primary key default gen_random_uuid(),
  source_type text not null check(source_type in ('correction','special')),
  source_id uuid not null,
  student_id uuid not null references public.students(id) on delete cascade,
  teacher_profile_id uuid not null references public.profiles(id) on delete restrict,
  scheduled_at timestamptz not null,
  ends_at timestamptz not null,
  room text not null,
  status public.makeup_status not null default 'scheduled',
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(source_type,source_id,student_id),
  check(ends_at>scheduled_at)
);
create index if not exists source_makeup_sessions_student_idx on public.source_makeup_sessions(student_id,scheduled_at desc);
alter table public.source_makeup_sessions enable row level security;
drop policy if exists source_makeup_sessions_staff on public.source_makeup_sessions;
create policy source_makeup_sessions_staff on public.source_makeup_sessions for all to authenticated
using(public.current_user_role() in ('admin','teacher','manager'))
with check(public.current_user_role() in ('admin','teacher','manager'));
grant select,insert,update,delete on public.source_makeup_sessions to authenticated;

create or replace function public.absence_makeup_board()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_role public.user_role;
begin
  if not public.is_staff() or public.current_user_role()='assistant' then raise exception '결석·보강 조회 권한이 없습니다.'; end if;
  v_role:=public.current_user_role();
  return jsonb_build_object(
    'isStaff',true,'role',v_role,
    'teachers',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name) from public.profiles p where p.is_active and p.role in ('admin','teacher','manager') and (v_role='admin' or p.id=auth.uid())),'[]'::jsonb),
    'items',coalesce((select jsonb_agg(row_data order by sort_date desc,student_name) from (
      select jsonb_build_object('attendanceId',a.id,'sourceId',a.id,'recordKind','absence','studentId',st.id,'studentName',st.name,'classId',c.id,'className',c.name,'subjectId',c.subject_id,'subjectName',coalesce(sub.name,c.subject,'과목 미지정'),'missedDate',l.lesson_date,'attendanceNote',coalesce(a.absence_reason,a.note),'sessionId',ms.id,'teacherId',ms.teacher_profile_id,'teacherName',tp.display_name,'scheduledAt',ms.scheduled_at,'endsAt',ms.ends_at,'room',ms.room,'status',ms.status,'note',ms.note,'source',case when exists(select 1 from public.class_makeup_attendees cm where cm.class_id=c.id and cm.student_id=st.id and cm.attendance_date=l.lesson_date) then 'class' else 'regular' end) row_data,
        coalesce(ms.scheduled_at,l.starts_at) sort_date,st.name student_name
      from public.attendance a join public.lessons l on l.id=a.lesson_id join public.classes c on c.id=l.class_id join public.students st on st.id=a.student_id left join public.academy_subjects sub on sub.id=c.subject_id left join public.makeup_sessions ms on ms.attendance_id=a.id left join public.profiles tp on tp.id=ms.teacher_profile_id
      where (a.status='absent' or ms.id is not null) and (v_role='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid()))
      union all
      select jsonb_build_object('attendanceId',null,'sourceId',r.id,'recordKind','absence','studentId',st.id,'studentName',st.name,'classId',scope.class_id,'className',coalesce(scope.class_name,'첨삭수업'),'subjectId',scope.subject_id,'subjectName',coalesce(r.subject,'과목 미지정'),'missedDate',r.correction_date,'attendanceNote',r.absence_reason,'sessionId',sm.id,'teacherId',sm.teacher_profile_id,'teacherName',tp.display_name,'scheduledAt',sm.scheduled_at,'endsAt',sm.ends_at,'room',sm.room,'status',sm.status,'note',sm.note,'source','correction') row_data,
        coalesce(sm.scheduled_at,((r.correction_date+r.start_time) at time zone 'Asia/Seoul')) sort_date,st.name student_name
      from public.correction_reports r join public.students st on st.id=r.student_id left join public.source_makeup_sessions sm on sm.source_type='correction' and sm.source_id=r.id and sm.student_id=r.student_id left join public.profiles tp on tp.id=sm.teacher_profile_id
      left join lateral (select c.id class_id,c.name class_name,c.subject_id from public.enrollments e join public.classes c on c.id=e.class_id where e.student_id=st.id and e.status='active' and c.active and (c.subject=r.subject or exists(select 1 from public.academy_subjects su where su.id=c.subject_id and su.name=r.subject)) order by c.name limit 1) scope on true
      where r.attendance_status='absent' and (v_role='admin' or exists(select 1 from public.correction_assignments ca where ca.id=r.assignment_id and (ca.tutor_profile_id=auth.uid() or ca.supervisor_profile_id=auth.uid())) or exists(select 1 from public.class_teachers ct where ct.class_id=scope.class_id and ct.profile_id=auth.uid()))
      union all
      select jsonb_build_object('attendanceId',null,'sourceId',sl.id,'recordKind','absence','studentId',st.id,'studentName',st.name,'classId',scope.class_id,'className',coalesce(scope.class_name,case when sl.kind='makeup' then '개별 보강' else '추가수업' end),'subjectId',sl.subject_id,'subjectName',coalesce(sub.name,'과목 미지정'),'missedDate',sl.lesson_date,'attendanceNote',ss.absence_reason,'sessionId',sm.id,'teacherId',sm.teacher_profile_id,'teacherName',coalesce(tp.display_name,owner.display_name),'scheduledAt',sm.scheduled_at,'endsAt',sm.ends_at,'room',coalesce(sm.room,sl.room),'status',sm.status,'note',sm.note,'source',case when sl.kind='makeup' then 'individual' else 'additional' end) row_data,
        coalesce(sm.scheduled_at,((sl.lesson_date+sl.starts_at) at time zone 'Asia/Seoul')) sort_date,st.name student_name
      from public.teacher_special_lessons sl join public.teacher_special_lesson_students ss on ss.session_id=sl.id join public.students st on st.id=ss.student_id left join public.academy_subjects sub on sub.id=sl.subject_id left join public.source_makeup_sessions sm on sm.source_type='special' and sm.source_id=sl.id and sm.student_id=st.id left join public.profiles tp on tp.id=sm.teacher_profile_id left join public.profiles owner on owner.id=sl.teacher_profile_id
      left join lateral (select c.id class_id,c.name class_name from public.enrollments e join public.classes c on c.id=e.class_id where e.student_id=st.id and e.status='active' and c.active and (sl.subject_id is null or c.subject_id=sl.subject_id) order by c.name limit 1) scope on true
      where ss.attendance_status='absent' and (v_role='admin' or sl.teacher_profile_id=auth.uid() or exists(select 1 from public.class_teachers ct where ct.class_id=scope.class_id and ct.profile_id=auth.uid()))
      union all
      select jsonb_build_object('attendanceId',null,'sourceId',null,'recordKind','schedule','studentId',st.id,'studentName',st.name,'classId',c.id,'className',c.name,'subjectId',c.subject_id,'subjectName',coalesce(sub.name,c.subject,'과목 미지정'),'missedDate',null,'attendanceNote',null,'sessionId',concat('class:',m.class_id,':',m.attendance_date),'teacherId',coalesce(l.teacher_profile_id,m.created_by),'teacherName',coalesce(lp.display_name,cp.display_name),'scheduledAt',coalesce(l.starts_at,((m.attendance_date+coalesce(sched.start_time,'18:00'::time)) at time zone 'Asia/Seoul')),'endsAt',coalesce(l.ends_at,((m.attendance_date+coalesce(sched.end_time,'20:00'::time)) at time zone 'Asia/Seoul')),'room',coalesce(l.room,c.room),'status',case when l.id is not null and (exists(select 1 from public.attendance ca where ca.lesson_id=l.id and ca.student_id=st.id) or nullif(trim(l.lesson_content),'') is not null or nullif(trim(l.homework_content),'') is not null or nullif(trim(l.exam_content),'') is not null) then 'completed' else 'scheduled' end,'note',null,'source','class') row_data,
        coalesce(l.starts_at,((m.attendance_date+coalesce(sched.start_time,'18:00'::time)) at time zone 'Asia/Seoul')) sort_date,st.name student_name
      from public.class_makeup_attendees m join public.classes c on c.id=m.class_id join public.students st on st.id=m.student_id left join public.academy_subjects sub on sub.id=c.subject_id left join lateral (select lesson.* from public.lessons lesson where lesson.class_id=m.class_id and lesson.lesson_date=m.attendance_date order by lesson.starts_at limit 1) l on true left join lateral (select cs.start_time,cs.end_time from public.class_schedules cs where cs.class_id=m.class_id order by cs.start_time limit 1) sched on true left join public.profiles lp on lp.id=l.teacher_profile_id left join public.profiles cp on cp.id=m.created_by
      where not exists(select 1 from public.attendance ca where ca.lesson_id=l.id and ca.student_id=st.id and ca.status='absent') and (v_role='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid()))
      union all
      select jsonb_build_object('attendanceId',null,'sourceId',sl.id,'recordKind','schedule','studentId',st.id,'studentName',st.name,'classId',scope.class_id,'className',coalesce(scope.class_name,'개별 보강'),'subjectId',sl.subject_id,'subjectName',coalesce(sub.name,'과목 미지정'),'missedDate',null,'attendanceNote',null,'sessionId',sl.id,'teacherId',sl.teacher_profile_id,'teacherName',tp.display_name,'scheduledAt',((sl.lesson_date+sl.starts_at) at time zone 'Asia/Seoul'),'endsAt',((sl.lesson_date+sl.ends_at) at time zone 'Asia/Seoul'),'room',sl.room,'status',case when sl.status='completed' then 'completed' else 'scheduled' end,'note',sl.note,'source','individual') row_data,
        ((sl.lesson_date+sl.starts_at) at time zone 'Asia/Seoul') sort_date,st.name student_name
      from public.teacher_special_lessons sl join public.teacher_special_lesson_students ss on ss.session_id=sl.id join public.students st on st.id=ss.student_id join public.profiles tp on tp.id=sl.teacher_profile_id left join public.academy_subjects sub on sub.id=sl.subject_id left join lateral (select c.id class_id,c.name class_name from public.enrollments e join public.classes c on c.id=e.class_id where e.student_id=st.id and e.status='active' and c.active and (sl.subject_id is null or c.subject_id=sl.subject_id) order by c.name limit 1) scope on true
      where sl.kind='makeup' and ss.attendance_status is distinct from 'absent' and (v_role='admin' or sl.teacher_profile_id=auth.uid() or exists(select 1 from public.class_teachers ct where ct.class_id=scope.class_id and ct.profile_id=auth.uid()))
    ) rows),'[]'::jsonb)
  );
end $$;

create or replace function public.staff_save_source_makeup(p_source text,p_source_id uuid,p_student_id uuid,p_teacher_id uuid,p_date date,p_start_time time,p_end_time time,p_room text,p_note text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; start_at timestamptz; end_at timestamptz; saved_id uuid; allowed boolean:=false;
begin
 if not public.is_staff() or public.current_user_role()='assistant' then raise exception '보강 등록 권한이 없습니다.'; end if; v_role:=public.current_user_role();
 if p_source not in ('correction','special') then raise exception '결석 출처를 확인해 주세요.'; end if;
 if p_start_time>=p_end_time then raise exception '종료 시간은 시작 시간보다 늦어야 합니다.'; end if; if nullif(trim(p_room),'') is null then raise exception '강의실을 입력해 주세요.'; end if;
 if not exists(select 1 from public.profiles p where p.id=p_teacher_id and p.is_active and p.role in ('admin','teacher','manager')) then raise exception '담당 교직원을 확인해 주세요.'; end if;
 if p_source='correction' then select exists(select 1 from public.correction_reports r where r.id=p_source_id and r.student_id=p_student_id and r.attendance_status='absent' and (v_role='admin' or exists(select 1 from public.correction_assignments ca where ca.id=r.assignment_id and (ca.tutor_profile_id=auth.uid() or ca.supervisor_profile_id=auth.uid())) or exists(select 1 from public.enrollments e join public.class_teachers ct on ct.class_id=e.class_id where e.student_id=r.student_id and e.status='active' and ct.profile_id=auth.uid()))) into allowed;
 else select exists(select 1 from public.teacher_special_lessons sl join public.teacher_special_lesson_students ss on ss.session_id=sl.id where sl.id=p_source_id and ss.student_id=p_student_id and ss.attendance_status='absent' and (v_role='admin' or sl.teacher_profile_id=auth.uid() or exists(select 1 from public.enrollments e join public.class_teachers ct on ct.class_id=e.class_id where e.student_id=ss.student_id and e.status='active' and ct.profile_id=auth.uid()))) into allowed; end if;
 if not allowed then raise exception '보강이 필요한 결석 기록을 찾을 수 없습니다.'; end if;
 start_at:=((p_date+p_start_time) at time zone 'Asia/Seoul'); end_at:=((p_date+p_end_time) at time zone 'Asia/Seoul');
 if exists(select 1 from public.makeup_sessions ms where ms.status='scheduled' and ms.scheduled_at<end_at and ms.ends_at>start_at and (ms.teacher_profile_id=p_teacher_id or ms.room=trim(p_room))) or exists(select 1 from public.source_makeup_sessions sm where not(sm.source_type=p_source and sm.source_id=p_source_id and sm.student_id=p_student_id) and sm.status='scheduled' and sm.scheduled_at<end_at and sm.ends_at>start_at and (sm.teacher_profile_id=p_teacher_id or sm.room=trim(p_room))) then raise exception '담당 선생님 또는 강의실에 겹치는 보강이 있습니다.'; end if;
 insert into public.source_makeup_sessions(source_type,source_id,student_id,teacher_profile_id,scheduled_at,ends_at,room,status,note) values(p_source,p_source_id,p_student_id,p_teacher_id,start_at,end_at,trim(p_room),'scheduled',nullif(trim(p_note),'')) on conflict(source_type,source_id,student_id) do update set teacher_profile_id=excluded.teacher_profile_id,scheduled_at=excluded.scheduled_at,ends_at=excluded.ends_at,room=excluded.room,status='scheduled',note=excluded.note,updated_at=now() returning id into saved_id;
 return saved_id;
end $$;

revoke all on function public.absence_makeup_board(),public.staff_save_source_makeup(text,uuid,uuid,uuid,date,time,time,text,text) from public,anon;
grant execute on function public.absence_makeup_board(),public.staff_save_source_makeup(text,uuid,uuid,uuid,date,time,time,text,text) to authenticated;
notify pgrst,'reload schema';
