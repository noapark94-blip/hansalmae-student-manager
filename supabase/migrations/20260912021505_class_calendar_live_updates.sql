create table public.staff_live_signals(
 key text primary key,topic text not null,entity_id uuid not null,class_id uuid,record_date date,
 changed_at timestamptz not null default clock_timestamp()
);
alter table public.staff_live_signals enable row level security;
revoke all on public.staff_live_signals from public,anon,authenticated;
grant select on public.staff_live_signals to authenticated;
create policy staff_live_signals_read on public.staff_live_signals for select to authenticated using(
 (select auth.uid()) is not null and (select public.is_staff()) and
 ((topic='calendar' and (select public.current_user_role())<>'assistant') or topic='classes' or
 (topic='record' and ((select public.current_user_role())='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=staff_live_signals.class_id and ct.profile_id=(select auth.uid())))))
);
create function public.notify_staff_live_change() returns trigger language plpgsql security definer set search_path=public as $$
declare r jsonb; entity uuid; cid uuid; d date; k text;
begin
 for r in select distinct x from jsonb_array_elements(case when tg_op='INSERT' then jsonb_build_array(to_jsonb(new)) when tg_op='DELETE' then jsonb_build_array(to_jsonb(old)) else jsonb_build_array(to_jsonb(old),to_jsonb(new)) end) x loop
  cid:=null;d:=null;
  if tg_argv[0]='calendar' then entity:=(r->>'id')::uuid;
  elsif tg_argv[0]='classes' then
    if tg_table_name='student_schedule_assignments' then select class_id into entity from public.class_schedules where id=(r->>'class_schedule_id')::uuid;
    else entity:=coalesce(r->>'class_id',r->>'id')::uuid;end if;cid:=entity;
  else
    if tg_table_name in ('lessons','class_lesson_roster_overrides') then cid:=(r->>'class_id')::uuid;d:=(r->>'lesson_date')::date;
    elsif tg_table_name='class_daily_notices' then cid:=(r->>'class_id')::uuid;d:=(r->>'notice_date')::date;
    else select class_id,lesson_date into cid,d from public.lessons where id=(r->>'lesson_id')::uuid;end if;
    entity:=cid;
  end if;
  if entity is null then continue;end if;
  k:=tg_argv[0]||':'||entity::text||coalesce(':'||d::text,'');
  insert into public.staff_live_signals(key,topic,entity_id,class_id,record_date) values(k,tg_argv[0],entity,cid,d)
  on conflict(key) do update set changed_at=clock_timestamp();
 end loop;return null;
end $$;
revoke all on function public.notify_staff_live_change() from public,anon,authenticated;
create trigger staff_live_change after insert or update or delete on public.academic_calendar_events for each row execute function public.notify_staff_live_change('calendar');
create trigger staff_live_change after insert or update or delete on public.classes for each row execute function public.notify_staff_live_change('classes');
create trigger staff_live_change after insert or update or delete on public.class_schedules for each row execute function public.notify_staff_live_change('classes');
create trigger staff_live_change after insert or update or delete on public.class_teachers for each row execute function public.notify_staff_live_change('classes');
create trigger staff_live_change after insert or update or delete on public.enrollments for each row execute function public.notify_staff_live_change('classes');
create trigger staff_live_change after insert or update or delete on public.lessons for each row execute function public.notify_staff_live_change('record');
create trigger staff_live_change after insert or update or delete on public.attendance for each row execute function public.notify_staff_live_change('record');
create trigger staff_live_change after insert or update or delete on public.lesson_exam_results for each row execute function public.notify_staff_live_change('record');
create trigger staff_live_change after insert or update or delete on public.lesson_homework_results for each row execute function public.notify_staff_live_change('record');
create trigger staff_live_change after insert or update or delete on public.class_daily_notices for each row execute function public.notify_staff_live_change('record');
create trigger staff_live_change after insert or update or delete on public.class_lesson_revision_drafts for each row execute function public.notify_staff_live_change('record');
alter publication supabase_realtime add table public.staff_live_signals;
CREATE OR REPLACE FUNCTION public.staff_academic_calendar_updates(p_year integer,p_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 if auth.uid() is null or not coalesce(public.is_staff(),false) or public.current_user_role()='assistant' then raise exception '일정 조회 권한이 없습니다.'; end if;
 return jsonb_build_object(
  'events',coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',e.id,'scope',e.event_scope,'school',e.school,'grade',e.grade,
      'category',e.category,'categoryLabel',coalesce(cat.label,'기타'),'title',e.title,
      'startsOn',e.starts_on,'endsOn',e.ends_on,'startsAt',e.starts_at,'endsAt',e.ends_at,
      'classId',e.class_id,'className',c.name,'teacherId',e.teacher_profile_id,
      'teacherName',tp.display_name,'note',e.note,'contactName',e.contact_name,
      'contactPhone',e.contact_phone,'location',e.location,'status',e.status,
      'createdBy',e.created_by,'authorName',author.display_name,
      'canEdit',(e.created_by=auth.uid() or public.current_user_role()='admin')
    ) order by e.starts_on,e.starts_at nulls last,e.title)
    from public.academic_calendar_events e
    left join public.academic_calendar_categories cat on cat.id=e.category and cat.scope=e.event_scope
    left join public.classes c on c.id=e.class_id
    left join public.profiles tp on tp.id=e.teacher_profile_id
    join public.profiles author on author.id=e.created_by
    where e.id=any(p_ids) and e.starts_on<=make_date(p_year,12,31) and e.ends_on>=make_date(p_year,1,1)
  ),'[]'::jsonb)
 );
end $function$;
revoke all on function public.staff_academic_calendar_updates(integer,uuid[]) from public,anon;
grant execute on function public.staff_academic_calendar_updates(integer,uuid[]) to authenticated;

create trigger staff_live_change after insert or update or delete on public.student_schedule_assignments for each row execute function public.notify_staff_live_change('classes');
create trigger staff_live_change after insert or update or delete on public.class_lesson_roster_overrides for each row execute function public.notify_staff_live_change('record');
