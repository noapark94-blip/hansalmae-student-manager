-- 학생 상세에서 정규·첨삭 출결과 두 종류의 보강 기록을 기간별로 함께 조회합니다.

create or replace function public.staff_student_attendance_makeup_history(p_student_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_staff() then
    raise exception '교직원만 학생 출결 기록을 확인할 수 있습니다.';
  end if;

  return jsonb_build_object(
    'regularAttendance', coalesce((
      select jsonb_agg(to_jsonb(q) order by q."lessonDate" desc, q.id)
      from (
        select
          a.id,
          l.lesson_date as "lessonDate",
          c.name as "className",
          a.status,
          a.note
        from public.attendance a
        join public.lessons l on l.id = a.lesson_id
        join public.classes c on c.id = l.class_id
        where a.student_id = p_student_id
        order by l.lesson_date desc, a.id
      ) q
    ), '[]'::jsonb),
    'correctionAttendance', coalesce((
      select jsonb_agg(to_jsonb(q) order by q."lessonDate" desc, q."startTime" desc, q.id)
      from (
        select
          r.id,
          r.correction_date as "lessonDate",
          (r.subject || ' 첨삭')::text as "className",
          r.subject,
          r.start_time as "startTime",
          r.attendance_status as status,
          case
            when r.attendance_status = 'late' and r.late_minutes is not null then r.late_minutes || '분 지각'
            when r.attendance_status = 'absent' then coalesce(nullif(r.absence_reason, ''), '결석 사유 없음')
            else null
          end as note
        from public.correction_reports r
        where r.student_id = p_student_id
          and r.attendance_status <> 'scheduled'
        order by r.correction_date desc, r.start_time desc, r.id
      ) q
    ), '[]'::jsonb),
    'makeups', coalesce((
      select jsonb_agg(to_jsonb(q) order by q."scheduledAt" desc, q.id)
      from (
        select
          ('absence:' || ms.id::text) as id,
          c.name as "className",
          l.lesson_date as "missedDate",
          ms.scheduled_at as "scheduledAt",
          ms.ends_at as "endsAt",
          ms.room,
          ms.status::text as status,
          p.display_name as "teacherName",
          ms.note,
          'absence_makeup'::text as "recordKind"
        from public.makeup_sessions ms
        join public.attendance a on a.id = ms.attendance_id
        join public.lessons l on l.id = a.lesson_id
        join public.classes c on c.id = l.class_id
        join public.profiles p on p.id = ms.teacher_profile_id
        where a.student_id = p_student_id

        union all

        select
          ('special:' || sl.id::text) as id,
          case when sl.kind = 'makeup' then '개별 보강' else '추가수업' end as "className",
          null::date as "missedDate",
          ((sl.lesson_date + sl.starts_at) at time zone 'Asia/Seoul') as "scheduledAt",
          ((sl.lesson_date + sl.ends_at) at time zone 'Asia/Seoul') as "endsAt",
          coalesce(sl.room, '') as room,
          case
            when ((sl.lesson_date + sl.ends_at) at time zone 'Asia/Seoul') < now() then 'completed'
            else 'scheduled'
          end as status,
          p.display_name as "teacherName",
          sl.note,
          case when sl.kind = 'makeup' then 'individual_makeup' else 'additional' end as "recordKind"
        from public.teacher_special_lessons sl
        join public.teacher_special_lesson_students ss on ss.session_id = sl.id
        join public.profiles p on p.id = sl.teacher_profile_id
        where ss.student_id = p_student_id
      ) q
    ), '[]'::jsonb)
  );
end
$$;

revoke all on function public.staff_student_attendance_makeup_history(uuid) from public;
grant execute on function public.staff_student_attendance_makeup_history(uuid) to authenticated;

notify pgrst, 'reload schema';
