-- 정규 출결의 결석과 개별 보강 등록을 한 화면에 모으고 담당 클래스 범위를 적용합니다.
create or replace function public.absence_makeup_board()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_role public.user_role;
begin
  if not public.is_staff() or public.current_user_role()='assistant' then raise exception '결석·보강 조회 권한이 없습니다.'; end if;
  v_role:=public.current_user_role();
  return jsonb_build_object(
    'isStaff',true,'role',v_role,
    'teachers',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name) from public.profiles p where p.is_active and p.role in ('admin','teacher','manager') and (v_role='admin' or p.id=auth.uid())),'[]'::jsonb),
    'items',coalesce((select jsonb_agg(row_data order by sort_date,student_name) from (
      select jsonb_build_object('attendanceId',a.id,'studentId',st.id,'studentName',st.name,'classId',c.id,'className',c.name,'subjectId',c.subject_id,'subjectName',coalesce(sub.name,c.subject,'과목 미지정'),'missedDate',l.lesson_date,'attendanceNote',a.note,'sessionId',ms.id,'teacherId',ms.teacher_profile_id,'teacherName',tp.display_name,'scheduledAt',ms.scheduled_at,'endsAt',ms.ends_at,'room',ms.room,'status',ms.status,'note',ms.note,'source','absence') row_data,
        coalesce(ms.scheduled_at,l.lesson_date::timestamptz) sort_date,st.name student_name
      from public.attendance a join public.lessons l on l.id=a.lesson_id join public.classes c on c.id=l.class_id join public.students st on st.id=a.student_id left join public.academy_subjects sub on sub.id=c.subject_id left join public.makeup_sessions ms on ms.attendance_id=a.id left join public.profiles tp on tp.id=ms.teacher_profile_id
      where (a.makeup_required or ms.id is not null) and (v_role='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid()))
      union all
      select jsonb_build_object('attendanceId',null,'studentId',st.id,'studentName',st.name,'classId',scope.class_id,'className',coalesce(scope.class_name,'개별 보강'),'subjectId',sl.subject_id,'subjectName',coalesce(sub.name,'과목 미지정'),'missedDate',null,'attendanceNote',null,'sessionId',sl.id,'teacherId',sl.teacher_profile_id,'teacherName',tp.display_name,'scheduledAt',((sl.lesson_date+sl.starts_at) at time zone 'Asia/Seoul'),'endsAt',((sl.lesson_date+sl.ends_at) at time zone 'Asia/Seoul'),'room',sl.room,'status',case when sl.status='completed' then 'completed' else 'scheduled' end,'note',sl.note,'source','special') row_data,
        ((sl.lesson_date+sl.starts_at) at time zone 'Asia/Seoul') sort_date,st.name student_name
      from public.teacher_special_lessons sl join public.teacher_special_lesson_students ss on ss.session_id=sl.id join public.students st on st.id=ss.student_id join public.profiles tp on tp.id=sl.teacher_profile_id left join public.academy_subjects sub on sub.id=sl.subject_id
      left join lateral (select c.id class_id,c.name class_name from public.enrollments e join public.classes c on c.id=e.class_id where e.student_id=st.id and e.status='active' and c.active and (sl.subject_id is null or c.subject_id=sl.subject_id) order by c.name limit 1) scope on true
      where sl.kind='makeup' and (v_role='admin' or sl.teacher_profile_id=auth.uid() or exists(select 1 from public.class_teachers ct where ct.class_id=scope.class_id and ct.profile_id=auth.uid()))
    ) rows),'[]'::jsonb)
  );
end $$;

create or replace function public.staff_save_makeup(p_attendance_id uuid,p_teacher_id uuid,p_date date,p_start_time time,p_end_time time,p_room text,p_note text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_role public.user_role; missed record; start_at timestamptz; end_at timestamptz; saved_id uuid;
begin
 if not public.is_staff() or public.current_user_role()='assistant' then raise exception '보강 등록 권한이 없습니다.'; end if; v_role:=public.current_user_role();
 if p_start_time>=p_end_time then raise exception '종료 시간은 시작 시간보다 늦어야 합니다.'; end if; if nullif(trim(p_room),'') is null then raise exception '강의실을 입력해 주세요.'; end if;
 select a.id,a.student_id,l.class_id into missed from public.attendance a join public.lessons l on l.id=a.lesson_id where a.id=p_attendance_id and a.makeup_required;
 if missed.id is null then raise exception '보강이 필요한 결석 기록을 찾을 수 없습니다.'; end if;
 if v_role<>'admin' and (p_teacher_id<>auth.uid() or not exists(select 1 from public.class_teachers ct where ct.class_id=missed.class_id and ct.profile_id=auth.uid())) then raise exception '담당 클래스의 결석만 보강 등록할 수 있습니다.'; end if;
 if not exists(select 1 from public.profiles p where p.id=p_teacher_id and p.is_active and p.role in ('admin','teacher','manager')) then raise exception '담당 교직원을 확인해 주세요.'; end if;
 start_at:=((p_date+p_start_time) at time zone 'Asia/Seoul'); end_at:=((p_date+p_end_time) at time zone 'Asia/Seoul');
 insert into public.makeup_sessions(attendance_id,teacher_profile_id,scheduled_at,ends_at,room,status,note) values(p_attendance_id,p_teacher_id,start_at,end_at,trim(p_room),'scheduled',nullif(trim(p_note),'')) on conflict(attendance_id) do update set teacher_profile_id=excluded.teacher_profile_id,scheduled_at=excluded.scheduled_at,ends_at=excluded.ends_at,room=excluded.room,status='scheduled',note=excluded.note returning id into saved_id;
 return saved_id;
end $$;
revoke all on function public.absence_makeup_board(),public.staff_save_makeup(uuid,uuid,date,time,time,text,text) from public,anon;
grant execute on function public.absence_makeup_board(),public.staff_save_makeup(uuid,uuid,date,time,time,text,text) to authenticated;
notify pgrst,'reload schema';
