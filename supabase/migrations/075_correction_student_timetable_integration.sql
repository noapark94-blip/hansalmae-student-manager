-- 학생 통합 주간 시간표에 이번 주 실제 첨삭 일정을 함께 표시합니다.
-- 고정 일정은 기본으로 보이고, 이번 주 move/cancel/extra 예외가 있으면 실제 일정으로 자동 치환됩니다.

create or replace function public.correction_timetable_staff(p_tutor uuid,p_supervisor uuid)
returns jsonb
language sql
stable
security definer
set search_path=public
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'name',q.name) order by q.sort_order,q.name),'[]'::jsonb)
  from (
    select p.id,p.display_name as name,0 as sort_order
    from public.profiles p where p.id=p_tutor
    union
    select p.id,p.display_name as name,1 as sort_order
    from public.profiles p where p.id=p_supervisor
  ) q
$$;

create or replace function public.staff_student_weekly_timetables()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_week_start date;
begin
  if not public.is_staff() then
    raise exception '교직원만 학생 시간표를 확인할 수 있습니다.';
  end if;

  v_week_start := current_date - (extract(isodow from current_date)::int - 1);

  return coalesce((
    select jsonb_agg(
      jsonb_build_object(
        'studentId',s.id,
        'rows',coalesce((
          select jsonb_agg(r.row_data order by r.weekday,r.start_time,r.sort_order,r.title)
          from (
            select
              cs.weekday::int as weekday,
              cs.start_time,
              0 as sort_order,
              c.name as title,
              jsonb_build_object(
                'id',cs.id::text,
                'weekday',cs.weekday,
                'startTime',cs.start_time,
                'endTime',cs.end_time,
                'className',c.name,
                'subject',c.subject,
                'color',c.color,
                'room',c.room,
                'teachers',coalesce((
                  select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name)
                  from public.class_teachers ct
                  join public.profiles p on p.id=ct.profile_id
                  where ct.class_id=c.id
                ),'[]'::jsonb)
              ) as row_data
            from public.enrollments e
            join public.classes c on c.id=e.class_id
            join public.class_schedules cs on cs.class_id=c.id
            where e.student_id=s.id
              and e.status='active'
              and c.active
              and (cs.valid_from is null or cs.valid_from<=current_date)
              and (cs.valid_until is null or cs.valid_until>=current_date)
              and (
                not exists(select 1 from public.student_schedule_assignments z where z.student_id=s.id)
                or exists(select 1 from public.student_schedule_assignments z where z.student_id=s.id and z.class_schedule_id=cs.id)
              )

            union all

            select
              a.weekday::int,
              a.start_time,
              1,
              a.subject||' 첨삭',
              jsonb_build_object(
                'id','correction-'||a.id::text,
                'weekday',a.weekday,
                'startTime',a.start_time,
                'endTime',a.end_time,
                'className',a.subject||' 첨삭',
                'subject','첨삭',
                'color','#922D61',
                'room',null,
                'teachers',public.correction_timetable_staff(a.tutor_profile_id,a.supervisor_profile_id)
              )
            from public.correction_assignments a
            where a.student_id=s.id
              and a.active
              and not exists(
                select 1
                from public.correction_schedule_exceptions x
                where x.assignment_id=a.id
                  and x.original_date=v_week_start+(a.weekday-1)
                  and x.kind in ('move','cancel')
              )

            union all

            select
              extract(isodow from x.target_date)::int,
              x.target_start_time,
              1,
              a.subject||' 첨삭',
              jsonb_build_object(
                'id','correction-move-'||x.id::text,
                'weekday',extract(isodow from x.target_date)::int,
                'startTime',x.target_start_time,
                'endTime',x.target_end_time,
                'className',a.subject||' 첨삭 · 변경',
                'subject','첨삭',
                'color','#922D61',
                'room',null,
                'teachers',public.correction_timetable_staff(a.tutor_profile_id,a.supervisor_profile_id)
              )
            from public.correction_assignments a
            join public.correction_schedule_exceptions x on x.assignment_id=a.id
            where a.student_id=s.id
              and a.active
              and x.kind='move'
              and x.original_date=v_week_start+(a.weekday-1)
              and x.target_date between v_week_start and v_week_start+6

            union all

            select
              extract(isodow from x.target_date)::int,
              x.target_start_time,
              2,
              a.subject||' 첨삭',
              jsonb_build_object(
                'id','correction-extra-'||x.id::text,
                'weekday',extract(isodow from x.target_date)::int,
                'startTime',x.target_start_time,
                'endTime',x.target_end_time,
                'className',a.subject||' 첨삭 · 추가',
                'subject','첨삭',
                'color','#922D61',
                'room',null,
                'teachers',public.correction_timetable_staff(a.tutor_profile_id,a.supervisor_profile_id)
              )
            from public.correction_assignments a
            join public.correction_schedule_exceptions x on x.assignment_id=a.id
            where a.student_id=s.id
              and a.active
              and x.kind='extra'
              and x.target_date between v_week_start and v_week_start+6
          ) r
        ),'[]'::jsonb)
      ) order by s.name
    )
    from public.students s
  ),'[]'::jsonb);
end
$$;

revoke all on function public.correction_timetable_staff(uuid,uuid) from public;
grant execute on function public.correction_timetable_staff(uuid,uuid),public.staff_student_weekly_timetables() to authenticated;
notify pgrst,'reload schema';
