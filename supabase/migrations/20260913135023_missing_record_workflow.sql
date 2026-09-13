-- Bounded staff work queue. No changes to existing attendance or publication functions.
create table public.record_work_requests (
 recipient_id uuid not null references public.profiles(id) on delete cascade,
 work_date date not null, requested_at timestamptz not null default now(),
 requested_by uuid not null references public.profiles(id),
 primary key(recipient_id,work_date)
);
alter table public.record_work_requests enable row level security;
revoke all on public.record_work_requests from public,anon,authenticated;
create table public.record_work_receipts (
 profile_id uuid not null references public.profiles(id) on delete cascade,
 day date not null, phase text not null, shown_at timestamptz not null default now(),
 primary key(profile_id,day,phase)
);
alter table public.record_work_receipts enable row level security;
revoke all on public.record_work_receipts from public,anon,authenticated;
create function public.staff_record_worklist(p_from date,p_to date) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare result jsonb; uid uuid:=auth.uid(); admin boolean; today date:=(now() at time zone 'Asia/Seoul')::date;
begin
 if uid is null or not exists(select 1 from public.profiles where id=uid and is_active and role in ('admin','sub_admin','teacher','assistant','manager')) then raise exception '교직원만 기록을 확인할 수 있습니다.';end if;
 admin:=public.current_user_role()='admin';
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>6 or p_to>today or p_from<today-30 then raise exception '최근 30일 내 최대 7일을 선택해 주세요.';end if;
  with days as (
    select generate_series(p_from,p_to,'1 day'::interval)::date occurrence_date
  ),
  regular_fixed as (
    select distinct e.student_id,'regular:'||cs.class_id||':'||d.occurrence_date||':'||cs.start_time expected_key,
      '정규수업' kind,c.name title,d.occurrence_date,cs.start_time,
      exists(select 1 from public.lessons l join public.attendance at on at.lesson_id=l.id and at.student_id=e.student_id where l.class_id=cs.class_id and l.lesson_date=d.occurrence_date and l.status='completed' and at.status::text in ('present','late','absent','excused')) completed
    from days d join public.class_schedules cs on cs.weekday=extract(isodow from d.occurrence_date)::smallint
      and (cs.valid_from is null or cs.valid_from<=d.occurrence_date) and (cs.valid_until is null or cs.valid_until>=d.occurrence_date)
    join public.classes c on c.id=cs.class_id and c.active
    join public.enrollments e on e.class_id=c.id and e.status='active' and e.started_on<=d.occurrence_date and (e.ended_on is null or e.ended_on>=d.occurrence_date)
    join public.students s on s.id=e.student_id and s.status in ('active','재원')
    where public.student_attends_class_on(e.student_id, cs.class_id, d.occurrence_date)
      and not exists(select 1 from public.schedule_exceptions x where x.class_id=cs.class_id and x.original_date=d.occurrence_date and x.kind in ('cancelled','changed','makeup'))
  ),
  regular_replacements as (
    select distinct e.student_id,'regular:'||x.class_id||':'||x.replacement_date||':'||coalesce(x.start_time,cs.start_time) expected_key,
      case when x.kind='makeup' then '보강수업' else '변경수업' end,c.name,x.replacement_date,coalesce(x.start_time,cs.start_time),
      exists(select 1 from public.lessons l join public.attendance at on at.lesson_id=l.id and at.student_id=e.student_id where l.class_id=x.class_id and l.lesson_date=x.replacement_date and l.status='completed' and at.status::text in ('present','late','absent','excused'))
    from public.schedule_exceptions x join public.class_schedules cs on cs.class_id=x.class_id and cs.weekday=extract(isodow from x.original_date)::smallint
    join public.classes c on c.id=x.class_id and c.active join public.enrollments e on e.class_id=c.id and e.status='active'
      and e.started_on<=x.replacement_date and (e.ended_on is null or e.ended_on>=x.replacement_date)
    join public.students s on s.id=e.student_id and s.status in ('active','재원')
    where (cs.valid_from is null or cs.valid_from<=x.original_date) and (cs.valid_until is null or cs.valid_until>=x.original_date) and public.student_attends_class_on(e.student_id,x.class_id,x.original_date) and x.kind in ('changed','makeup') and x.replacement_date between p_from and p_to
  ),
  class_makeups as (
    select distinct m.student_id,'class-makeup:'||m.class_id||':'||m.attendance_date expected_key,'보강수업',c.name,m.attendance_date,cs.start_time,
      exists(select 1 from public.lessons l join public.attendance at on at.lesson_id=l.id and at.student_id=m.student_id where l.class_id=m.class_id and l.lesson_date=m.attendance_date and l.status='completed' and at.status::text in ('present','late','absent','excused'))
    from public.class_makeup_attendees m join public.classes c on c.id=m.class_id
    left join public.class_schedules cs on cs.class_id=m.class_id and cs.weekday=extract(isodow from m.attendance_date)::smallint
    join public.students s on s.id=m.student_id and s.status in ('active','재원') where m.attendance_date between p_from and p_to
  ),
  special_lessons as (
    select a.student_id,'special:'||l.id expected_key,case when l.kind='makeup' then '개별 보강' else '추가수업' end,
      coalesce(sub.name,case when l.kind='makeup' then '보강' else '추가수업' end),l.lesson_date,l.starts_at,
      l.status='completed' and a.attendance_status is not null
    from public.teacher_special_lessons l join public.teacher_special_lesson_students a on a.session_id=l.id
    join public.students s on s.id=a.student_id and s.status in ('active','재원') left join public.academy_subjects sub on sub.id=l.subject_id
    where l.lesson_date between p_from and p_to and l.status<>'cancelled'
  ),
  correction_fixed as (
    select a.student_id,'correction:'||a.id||':'||d.occurrence_date||':'||a.start_time expected_key,'첨삭수업',a.subject||' 첨삭',d.occurrence_date,a.start_time,
      exists(select 1 from public.correction_reports r where r.assignment_id=a.id and r.student_id=a.student_id and r.correction_date=d.occurrence_date and r.start_time=a.start_time and r.published and r.attendance_status<>'scheduled')
    from days d join public.correction_assignments a on a.active and a.weekday=extract(isodow from d.occurrence_date)::smallint
      and (a.valid_from is null or a.valid_from<=d.occurrence_date) and (a.valid_until is null or a.valid_until>=d.occurrence_date)
    join public.students s on s.id=a.student_id and s.status in ('active','재원')
    where not exists(select 1 from public.correction_schedule_exceptions x where x.assignment_id=a.id and x.original_date=d.occurrence_date and x.kind in ('move','cancel'))
  ),
  correction_changes as (
    select a.student_id,'correction:'||a.id||':'||x.target_date||':'||x.target_start_time expected_key,'첨삭수업',a.subject||case when x.kind='extra' then ' 추가 첨삭' else ' 첨삭' end,x.target_date,x.target_start_time,
      exists(select 1 from public.correction_reports r where r.assignment_id=a.id and r.student_id=a.student_id and r.correction_date=x.target_date and r.start_time=x.target_start_time and r.published and r.attendance_status<>'scheduled')
    from public.correction_schedule_exceptions x join public.correction_assignments a on a.id=x.assignment_id and a.active
    join public.students s on s.id=a.student_id and s.status in ('active','재원') where x.kind in ('move','extra') and x.target_date between p_from and p_to
  ),
  roster_additions as (
    select distinct o.student_id,'regular:'||o.class_id||':'||o.lesson_date||':'||coalesce((l.starts_at at time zone 'Asia/Seoul')::time,cs.start_time,'00:00'::time) expected_key,
      '정규수업',c.name,o.lesson_date,coalesce((l.starts_at at time zone 'Asia/Seoul')::time,cs.start_time),
      exists(select 1 from public.lessons ll join public.attendance a on a.lesson_id=ll.id and a.student_id=o.student_id where ll.class_id=o.class_id and ll.lesson_date=o.lesson_date and ll.status='completed' and a.status::text in ('present','late','absent','excused'))
    from public.class_lesson_roster_overrides o join public.classes c on c.id=o.class_id
    join public.students s on s.id=o.student_id and s.status in ('active','재원')
    left join public.lessons l on l.class_id=o.class_id and l.lesson_date=o.lesson_date
    left join public.class_schedules cs on cs.class_id=o.class_id and cs.weekday=extract(isodow from o.lesson_date)
    where o.lesson_date between p_from and p_to
      and not exists(select 1 from public.schedule_exceptions x where x.class_id=o.class_id and x.original_date=o.lesson_date and x.kind in ('cancelled','changed','makeup'))
  ),
  scheduled_expected as (
    select * from regular_fixed union select * from regular_replacements union select * from class_makeups
    union select * from roster_additions
    union all select * from special_lessons union all select * from correction_fixed union select * from correction_changes
  ),
 identified as (
 select distinct on (e.student_id,case when split_part(expected_key,':',1) in ('regular','class-makeup') then 'class:'||split_part(expected_key,':',2)||':'||occurrence_date else expected_key end) e.*,split_part(expected_key,':',1) source,split_part(expected_key,':',2)::uuid entity_id
 from scheduled_expected e where not coalesce(completed,false)
 order by e.student_id,case when split_part(expected_key,':',1) in ('regular','class-makeup') then 'class:'||split_part(expected_key,':',2)||':'||occurrence_date else expected_key end,case when kind like '%보강%' then 0 else 1 end,start_time
 ),
 enriched as (
 select e.*,c.id class_id,sp.id session_id,ca.id assignment_id,
 coalesce(case when e.source='special' then sp.ends_at when e.source='correction' then coalesce(cx.target_end_time,ca.end_time) else coalesce((l.ends_at at time zone 'Asia/Seoul')::time,(select max(x.end_time) from public.schedule_exceptions x where x.class_id=c.id and x.replacement_date=e.occurrence_date and x.kind in ('changed','makeup'))) end,
 (select max(sc.end_time) from public.class_schedules sc where sc.class_id=c.id and sc.weekday=extract(isodow from e.occurrence_date) and (e.start_time is null or sc.start_time=e.start_time)),e.start_time+interval '90 minutes','23:59'::time) end_time,
 case when e.source='special' then array[sp.teacher_profile_id]
 when e.source='correction' then array_remove(array[coalesce(ca.tutor_profile_id,ca.teacher_profile_id),ca.supervisor_profile_id],null)||array(select sa.assistant_profile_id from public.correction_slot_assistants sa where sa.weekday=extract(isodow from e.occurrence_date) and sa.start_time=e.start_time)
 else case when l.teacher_profile_id is not null then array[l.teacher_profile_id] else array(select ct.profile_id from public.class_teachers ct where ct.class_id=c.id) end end owner_ids,
 case when e.source='special' then exists(select 1 from public.teacher_special_lesson_students a where a.session_id=sp.id and a.student_id=e.student_id and a.attendance_status is not null)
 when e.source='correction' then exists(select 1 from public.correction_reports r where r.assignment_id=ca.id and r.student_id=e.student_id and r.correction_date=e.occurrence_date and r.start_time=e.start_time and r.attendance_status<>'scheduled')
 else exists(select 1 from public.attendance a where a.lesson_id=l.id and a.student_id=e.student_id and a.status::text in ('present','late','absent','excused')) end has_attendance
 from identified e
 left join public.classes c on e.source in ('regular','class-makeup') and c.id=e.entity_id
 left join lateral(select * from public.lessons ll where ll.class_id=c.id and ll.lesson_date=e.occurrence_date order by ll.starts_at limit 1) l on true
 left join public.teacher_special_lessons sp on e.source='special' and sp.id=e.entity_id
 left join public.correction_assignments ca on e.source='correction' and ca.id=e.entity_id
 left join public.correction_schedule_exceptions cx on cx.assignment_id=ca.id and cx.target_date=e.occurrence_date and cx.target_start_time=e.start_time and cx.kind in ('move','extra')
 where coalesce(l.status,'')<>'cancelled'
 ),
 scoped as (
 select e.*,coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name,p.id) from public.profiles p where p.id=any(e.owner_ids) and p.is_active and p.role in ('admin','sub_admin','teacher','assistant','manager')),'[]'::jsonb) owners
 from enriched e where admin or uid=any(e.owner_ids)
 )
 select coalesce(jsonb_agg(item order by item->>'date',item->>'time',item->>'studentName'),'[]'::jsonb) into result from (
 select distinct jsonb_build_object('key',e.expected_key||':'||s.id,'source',e.source,'kind',e.kind,'title',e.title,'date',e.occurrence_date,'time',to_char(e.start_time,'HH24:MI'),'endTime',to_char(e.end_time,'HH24:MI'),
 'due',((e.occurrence_date+e.end_time) at time zone 'Asia/Seoul')<=now(),
 'studentId',s.id,'studentName',s.name,'classId',e.class_id,'sessionId',e.session_id,'assignmentId',e.assignment_id,'owners',e.owners,
 'reason',case when e.has_attendance then '완료 처리 필요' else '출결 입력 필요' end,
 'requestedAt',(select max(r.requested_at) from public.record_work_requests r where r.recipient_id=uid and r.work_date=e.occurrence_date)) item
 from scoped e join public.students s on s.id=e.student_id
 ) q;
 return result;
end $$;
revoke all on function public.staff_record_worklist(date,date) from public,anon;
grant execute on function public.staff_record_worklist(date,date) to authenticated;

create function public.staff_request_missing_records(p_date date,p_recipient uuid default null) returns jsonb
language plpgsql security definer set search_path=public as $$
declare items jsonb; sent integer; candidates integer;
begin
 if auth.uid() is null or not exists(select 1 from public.profiles where id=auth.uid() and is_active and role='admin') then raise exception '관리자만 기록 요청을 보낼 수 있습니다.';end if;
 items:=public.staff_record_worklist(p_date,p_date);
 with owners as (
 select distinct (o->>'id')::uuid id from jsonb_array_elements(items) i cross join lateral jsonb_array_elements(i->'owners') o
 where (i->>'due')::boolean and (p_recipient is null or (o->>'id')::uuid=p_recipient)
 ), inserted as (
 insert into public.record_work_requests(recipient_id,work_date,requested_by)
 select id,p_date,auth.uid() from owners
 on conflict(recipient_id,work_date) do update set requested_at=now(),requested_by=auth.uid()
 where record_work_requests.requested_at<now()-interval '30 minutes' returning recipient_id
 ) select (select count(*) from owners),count(*) into candidates,sent from inserted;
 return jsonb_build_object('sent',sent,'cooldown',candidates-sent);
end $$;
revoke all on function public.staff_request_missing_records(date,uuid) from public,anon;
grant execute on function public.staff_request_missing_records(date,uuid) to authenticated;

-- Claims prevent the same automatic reminder appearing again on another tab/device.
create function public.staff_claim_record_reminder() returns jsonb
language plpgsql security definer set search_path=public as $$
declare today date:=(now() at time zone 'Asia/Seoul')::date; items jsonb; phase text; claimed integer; requested text; due_count integer;
begin
 items:=public.staff_record_worklist(today-6,today);
 select count(*),max(i->>'requestedAt') into due_count,requested from jsonb_array_elements(items) i
 where (i->>'due')::boolean and exists(select 1 from jsonb_array_elements(i->'owners') o where o->>'id'=auth.uid()::text);
 if due_count=0 then return null;end if;
 phase:=case when (now() at time zone 'Asia/Seoul')::time>='21:30' then 'closing' else 'after-class' end;
 if requested is not null and requested::timestamptz>now()-interval '1 day' then phase:='request:'||requested;end if;
 insert into public.record_work_receipts(profile_id,day,phase) values(auth.uid(),today,phase) on conflict do nothing;
 get diagnostics claimed=row_count;
 return case when claimed>0 then jsonb_build_object('count',due_count,'requested',phase like 'request:%') else null end;
end $$;
revoke all on function public.staff_claim_record_reminder() from public,anon;
grant execute on function public.staff_claim_record_reminder() to authenticated;
notify pgrst,'reload schema';
