-- 담당 클래스 권한을 유지하면서 기존 보강 시간·강의실 중복 검사를 보존합니다.
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
 if exists(select 1 from public.class_schedules cs join public.class_teachers ct on ct.class_id=cs.class_id and ct.profile_id=p_teacher_id where cs.weekday=extract(isodow from p_date)::smallint and cs.start_time<p_end_time and cs.end_time>p_start_time and (cs.valid_from is null or cs.valid_from<=p_date) and (cs.valid_until is null or cs.valid_until>=p_date) and not exists(select 1 from public.schedule_exceptions se where se.class_id=cs.class_id and se.original_date=p_date and se.kind='cancelled')) then raise exception '담당 선생님에게 겹치는 정규 수업이 있습니다.'; end if;
 if exists(select 1 from public.class_schedules cs join public.classes c on c.id=cs.class_id where cs.weekday=extract(isodow from p_date)::smallint and c.room=trim(p_room) and cs.start_time<p_end_time and cs.end_time>p_start_time and (cs.valid_from is null or cs.valid_from<=p_date) and (cs.valid_until is null or cs.valid_until>=p_date) and not exists(select 1 from public.schedule_exceptions se where se.class_id=cs.class_id and se.original_date=p_date and se.kind='cancelled')) then raise exception '선택한 강의실에 겹치는 정규 수업이 있습니다.'; end if;
 if exists(select 1 from public.makeup_sessions ms where ms.attendance_id<>p_attendance_id and ms.status='scheduled' and ms.scheduled_at<end_at and ms.ends_at>start_at and (ms.teacher_profile_id=p_teacher_id or ms.room=trim(p_room))) then raise exception '담당 선생님 또는 강의실에 겹치는 보강이 있습니다.'; end if;
 insert into public.makeup_sessions(attendance_id,teacher_profile_id,scheduled_at,ends_at,room,status,note) values(p_attendance_id,p_teacher_id,start_at,end_at,trim(p_room),'scheduled',nullif(trim(p_note),'')) on conflict(attendance_id) do update set teacher_profile_id=excluded.teacher_profile_id,scheduled_at=excluded.scheduled_at,ends_at=excluded.ends_at,room=excluded.room,status='scheduled',note=excluded.note returning id into saved_id;
 return saved_id;
end $$;
revoke all on function public.staff_save_makeup(uuid,uuid,date,time,time,text,text) from public,anon;
grant execute on function public.staff_save_makeup(uuid,uuid,date,time,time,text,text) to authenticated;
notify pgrst,'reload schema';
