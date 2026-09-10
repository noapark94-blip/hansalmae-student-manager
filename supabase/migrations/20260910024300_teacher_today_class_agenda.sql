create or replace function public.staff_class_agenda(p_date date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
 if not public.is_staff() then raise exception '교직원만 조회할 수 있습니다.'; end if;
 with allowed as (
 select c.* from classes c where c.active and (public.current_user_role()='admin' or exists(select 1 from class_teachers t where t.class_id=c.id and t.profile_id=auth.uid()))
 ), slots as (
 select cs.id::text key,c.id class_id,null::uuid session_id,c.name,c.subject,c.color,c.room,cs.start_time,cs.end_time,'정규수업' kind
 from allowed c join class_schedules cs on cs.class_id=c.id
 where cs.weekday=extract(isodow from p_date) and (cs.valid_from is null or cs.valid_from<=p_date) and (cs.valid_until is null or cs.valid_until>=p_date)
 and not exists(select 1 from schedule_exceptions x where x.class_id=c.id and x.original_date=p_date and x.kind in ('cancelled','changed','makeup'))
 union all
 select x.id::text||':'||cs.id,c.id,null::uuid,c.name,c.subject,c.color,coalesce(x.room,c.room),coalesce(x.start_time,cs.start_time),coalesce(x.end_time,cs.end_time),case when x.kind='makeup' then '보강수업' else '변경수업' end
 from allowed c join schedule_exceptions x on x.class_id=c.id
 join class_schedules cs on cs.class_id=c.id and cs.weekday=extract(isodow from x.original_date)
 where x.replacement_date=p_date and x.kind in ('changed','makeup')
 ), makeup_slots as (
 select distinct on (m.class_id) 'makeup:'||m.class_id key,c.id class_id,null::uuid session_id,c.name,c.subject,c.color,c.room,
 coalesce((l.starts_at at time zone 'Asia/Seoul')::time,cs.start_time,'18:00'::time) start_time,
 coalesce((l.ends_at at time zone 'Asia/Seoul')::time,cs.end_time,'20:00'::time) end_time,'보강수업' kind
 from class_makeup_attendees m join allowed c on c.id=m.class_id
 left join lessons l on l.class_id=c.id and l.lesson_date=p_date
 left join class_schedules cs on cs.class_id=c.id
 where m.attendance_date=p_date and not exists(select 1 from slots s where s.class_id=c.id)
 order by m.class_id,l.starts_at,cs.start_time
 ), all_slots as (select * from slots union all select * from makeup_slots), entries as (
 select s.*, exists(select 1 from lessons l where l.class_id=s.class_id and l.lesson_date=p_date and l.status='completed') completed,
 (select count(*) from students st where st.status in ('active','재원') and public.student_attends_class_on(st.id,s.class_id,p_date)) student_count,
 array(select t.profile_id from class_teachers t where t.class_id=s.class_id) teacher_ids
 from all_slots s
 union all
 select 'special:'||l.id,null::uuid,l.id,coalesce(a.name,'수업')||case when l.kind='makeup' then ' 보강' else ' 추가수업' end,
 coalesce(a.main_subject,a.name,'수업'),'#8e888b',l.room,l.starts_at,l.ends_at,case when l.kind='makeup' then '개별 보강' else '추가수업' end,
 l.status='completed',(select count(*) from teacher_special_lesson_students st where st.session_id=l.id),array[l.teacher_profile_id]
 from teacher_special_lessons l left join academy_subjects a on a.id=l.subject_id
 where l.lesson_date=p_date and (public.current_user_role()='admin' or l.teacher_profile_id=auth.uid())
 )
 select coalesce(jsonb_agg(jsonb_build_object('key',key,'classId',class_id,'sessionId',session_id,'name',name,'subject',subject,'color',color,'room',room,'startTime',to_char(start_time,'HH24:MI'),'endTime',to_char(end_time,'HH24:MI'),'kind',kind,'completed',completed,'studentCount',student_count,'teacherIds',teacher_ids) order by start_time,name),'[]'::jsonb) into result from entries;
 return result;
end $$;
revoke all on function public.staff_class_agenda(date) from public,anon;
grant execute on function public.staff_class_agenda(date) to authenticated;

