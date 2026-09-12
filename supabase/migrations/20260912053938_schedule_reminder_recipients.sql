-- NULL retains the legacy default: the assigned teacher. Explicit arrays are selected recipients.
alter table public.academic_calendar_events add column reminder_recipient_ids uuid[];
alter table public.teacher_special_lessons add column reminder_recipient_ids uuid[];
create index calendar_reminder_recipients on public.academic_calendar_events using gin(reminder_recipient_ids) where reminder_enabled;
create index special_reminder_recipients on public.teacher_special_lessons using gin(reminder_recipient_ids) where reminder_enabled;

create or replace function public.schedule_reminder_version() returns trigger language plpgsql set search_path=public as $$
declare fields text[]; recipients uuid[]; validate boolean;
begin
 fields:=case when tg_table_name='academic_calendar_events' then array['reminder_enabled','teacher_profile_id','starts_on','ends_on','starts_at','ends_at','title','note','contact_name','location','status','category','event_scope'] else array['reminder_enabled','teacher_profile_id','lesson_date','starts_at','ends_at','kind','subject_id','room','note','status'] end;
 if new.reminder_recipient_ids is not null then
  new.reminder_recipient_ids:=array(select distinct x from unnest(new.reminder_recipient_ids) x order by x);
 end if;
 recipients:=coalesce(new.reminder_recipient_ids,array_remove(array[new.teacher_profile_id],null));
 validate:=tg_op='INSERT';
 if tg_op='UPDATE' then
  validate:=new.reminder_enabled is distinct from old.reminder_enabled or new.reminder_recipient_ids is distinct from old.reminder_recipient_ids or (new.reminder_recipient_ids is null and new.teacher_profile_id is distinct from old.teacher_profile_id);
  if exists(select 1 from unnest(fields) k where to_jsonb(new)->k is distinct from to_jsonb(old)->k) then new.reminder_version:=gen_random_uuid();end if;
 end if;
 if new.reminder_enabled and validate then
  if cardinality(recipients)=0 then raise exception '알림 받을 선생님을 한 명 이상 선택해 주세요.';end if;
  if exists(select 1 from unnest(recipients) x where not exists(select 1 from public.profiles p where p.id=x and p.is_active and p.role in ('admin','sub_admin','teacher','assistant','manager'))) then raise exception '활동 중인 교직원만 알림 대상으로 선택할 수 있습니다.';end if;
 end if;
 return new;
end $$;
create or replace function public.notify_schedule_reminder() returns trigger language plpgsql security definer set search_path=public as $$
declare rows jsonb; uid uuid;
begin
 if tg_op='UPDATE' and new.reminder_version=old.reminder_version and new.reminder_recipient_ids is not distinct from old.reminder_recipient_ids then return null;end if;
 rows:=case when tg_op='INSERT' then jsonb_build_array(to_jsonb(new)) when tg_op='DELETE' then jsonb_build_array(to_jsonb(old)) else jsonb_build_array(to_jsonb(old),to_jsonb(new)) end;
 for uid in
  select distinct (x.value #>> '{}')::uuid
  from jsonb_array_elements(rows) r
  cross join lateral jsonb_array_elements(case when r->'reminder_recipient_ids' is null or r->'reminder_recipient_ids'='null'::jsonb then jsonb_build_array(r->'teacher_profile_id') else r->'reminder_recipient_ids' end) x
  where coalesce((r->>'reminder_enabled')::boolean,false) and x.value<>'null'::jsonb
 loop
  insert into public.staff_live_signals(key,topic,entity_id) values('reminders:'||uid,'reminders',uid) on conflict(key) do update set changed_at=clock_timestamp();
 end loop;
 return null;
end $$;

create function public.staff_schedule_reminder_people() returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
 if auth.uid() is null or not coalesce(public.is_staff(),false) then raise exception '교직원만 확인할 수 있습니다.';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',display_name,'role',role) order by display_name,id) from public.profiles where is_active and role in ('admin','sub_admin','teacher','assistant','manager')),'[]'::jsonb);
end $$;
revoke all on function public.staff_schedule_reminder_people() from public,anon;
grant execute on function public.staff_schedule_reminder_people() to authenticated;

CREATE OR REPLACE FUNCTION public.calendar_edit_values(e academic_calendar_events)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
 select jsonb_build_object(
 'reminderRecipientIds',coalesce(e.reminder_recipient_ids,array_remove(array[e.teacher_profile_id],null)),'reminderEnabled',e.reminder_enabled,'kind',jsonb_build_object('scope',e.event_scope,'category',e.category),
 'timing',jsonb_build_object('startsOn',e.starts_on::text,'endsOn',e.ends_on::text,'startsAt',coalesce(to_char(e.starts_at,'HH24:MI'),''),'endsAt',coalesce(to_char(e.ends_at,'HH24:MI'),'')),
 'school',coalesce(e.school,''),'grade',coalesce(e.grade,''),'title',e.title,
 'classId',coalesce(e.class_id::text,''),'teacherId',coalesce(e.teacher_profile_id::text,''),
 'note',coalesce(e.note,''),'contactName',coalesce(e.contact_name,''),'contactPhone',coalesce(e.contact_phone,''),
 'location',coalesce(e.location,''),'status',e.status)
$function$
;

CREATE OR REPLACE FUNCTION public.current_schedule_reminders()
 RETURNS TABLE(source text, source_id uuid, version uuid, due date, payload jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select 'calendar',e.id,e.reminder_version,e.starts_on,jsonb_build_object('source','calendar','id',e.id,'version',e.reminder_version,'date',e.starts_on,'time',to_char(e.starts_at,'HH24:MI'),'endTime',to_char(e.ends_at,'HH24:MI'),'title',e.title,'kind',coalesce(c.label,'일정'),'person',e.contact_name,'place',e.location,'note',e.note)
 from public.academic_calendar_events e left join public.academic_calendar_categories c on c.id=e.category and c.scope=e.event_scope
 where public.is_staff() and (e.reminder_recipient_ids @> array[auth.uid()] or (e.reminder_recipient_ids is null and e.teacher_profile_id=auth.uid())) and e.reminder_enabled and e.status not in ('cancelled','completed','no_show','enrolled') and e.starts_on between (now() at time zone 'Asia/Seoul')::date-30 and (now() at time zone 'Asia/Seoul')::date
 union all
 select 'special',l.id,l.reminder_version,l.lesson_date,jsonb_build_object('source','special','id',l.id,'version',l.reminder_version,'date',l.lesson_date,'time',to_char(l.starts_at,'HH24:MI'),'endTime',to_char(l.ends_at,'HH24:MI'),'title',coalesce(s.name,'')||case when l.kind='makeup' then ' 보강수업' else ' 추가수업' end,'kind',case when l.kind='makeup' then '보강' else '추가수업' end,'person',(select string_agg(st.name,' · ' order by st.name) from public.teacher_special_lesson_students ss join public.students st on st.id=ss.student_id where ss.session_id=l.id),'place',l.room,'note',l.note)
 from public.teacher_special_lessons l left join public.academy_subjects s on s.id=l.subject_id
 where public.is_staff() and (l.reminder_recipient_ids @> array[auth.uid()] or (l.reminder_recipient_ids is null and l.teacher_profile_id=auth.uid())) and l.reminder_enabled and l.status<>'completed' and l.lesson_date between (now() at time zone 'Asia/Seoul')::date-30 and (now() at time zone 'Asia/Seoul')::date
$function$
;

CREATE OR REPLACE FUNCTION public.staff_academic_calendar_board(p_year integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 if not public.is_staff() or public.current_user_role()='assistant' then raise exception '일정 조회 권한이 없습니다.'; end if;
 return jsonb_build_object(
  'events',coalesce((
    select jsonb_agg(jsonb_build_object(
      'reminderRecipientIds',coalesce(e.reminder_recipient_ids,array_remove(array[e.teacher_profile_id],null)),'reminderEnabled',e.reminder_enabled,'id',e.id,'scope',e.event_scope,'school',e.school,'grade',e.grade,
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
    where e.starts_on<=make_date(p_year,12,31) and e.ends_on>=make_date(p_year,1,1)
  ),'[]'::jsonb),
  'categories',coalesce((select jsonb_agg(jsonb_build_object(
    'id',cat.id,'scope',cat.scope,'label',cat.label,'sortOrder',cat.sort_order,'active',cat.is_active
  ) order by cat.scope,cat.sort_order,cat.label) from public.academic_calendar_categories cat),'[]'::jsonb),
  'schools',coalesce((select jsonb_agg(x.school order by x.school) from (select distinct trim(s.school) school from public.students s where nullif(trim(s.school),'') is not null) x),'[]'::jsonb),
  'classes',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'school',null,'subject',coalesce(sub.name,c.subject),'teacherIds',coalesce((select jsonb_agg(ct.profile_id) from public.class_teachers ct where ct.class_id=c.id),'[]'::jsonb)) order by c.name) from public.classes c left join public.academy_subjects sub on sub.id=c.subject_id where c.active and (public.current_user_role()='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid()))),'[]'::jsonb),
  'teachers',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name) from public.profiles p where p.is_active and p.role in ('admin','teacher','sub_admin','manager') and (public.current_user_role()='admin' or p.id=auth.uid())),'[]'::jsonb)
 );
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_academic_calendar_updates(p_year integer, p_ids uuid[])
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
      'reminderRecipientIds',coalesce(e.reminder_recipient_ids,array_remove(array[e.teacher_profile_id],null)),'reminderEnabled',e.reminder_enabled,'id',e.id,'scope',e.event_scope,'school',e.school,'grade',e.grade,
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
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_patch_calendar_event(p_id uuid, p_base jsonb, p_changes jsonb, p_delete boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare e public.academic_calendar_events; v jsonb; conflicts jsonb; m jsonb;
begin
 if auth.uid() is null or not coalesce(public.is_staff(),false) or public.current_user_role()='assistant' then raise exception '일정 수정 권한이 없습니다.'; end if;
 select * into e from public.academic_calendar_events where id=p_id for update;
 if not found then raise exception '이미 삭제된 일정입니다. 입력 내용은 유지됩니다.'; end if;
 if e.created_by<>auth.uid() and public.current_user_role()<>'admin' then raise exception '일정 수정 권한이 없습니다.'; end if;
 v:=public.calendar_edit_values(e);
 conflicts:=public.settings_edit_conflicts(p_base,v,case when p_delete then p_base else p_changes end);
 if jsonb_array_length(conflicts)>0 then return jsonb_build_object('conflicts',conflicts,'values',v); end if;
 if p_delete then perform public.staff_delete_academic_calendar_event(p_id); return jsonb_build_object('saved',true); end if;
 m:=v||p_changes;
 perform public.staff_save_calendar_event(p_id,m#>>'{kind,scope}',m->>'school',m->>'grade',m#>>'{kind,category}',m->>'title',
 (m#>>'{timing,startsOn}')::date,(m#>>'{timing,endsOn}')::date,nullif(m#>>'{timing,startsAt}','')::time,nullif(m#>>'{timing,endsAt}','')::time,
 nullif(m->>'classId','')::uuid,nullif(m->>'teacherId','')::uuid,m->>'note',m->>'contactName',m->>'contactPhone',m->>'location',m->>'status');
 update public.academic_calendar_events set reminder_enabled=coalesce((m->>'reminderEnabled')::boolean,false), reminder_recipient_ids=case when p_changes ? 'reminderRecipientIds' then array(select value::uuid from jsonb_array_elements_text(m->'reminderRecipientIds')) else e.reminder_recipient_ids end where id=p_id;
 return jsonb_build_object('saved',true);
end $function$
;

CREATE OR REPLACE FUNCTION public.staff_save_calendar_with_reminder(p_values jsonb, p_reminder_enabled boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid;v jsonb:=p_values;begin
 if not public.is_staff() then raise exception '저장 권한이 없습니다.';end if;
 v_id:=public.staff_save_calendar_event(nullif(v->>'p_id','')::uuid,v->>'p_scope',v->>'p_school',v->>'p_grade',v->>'p_category',v->>'p_title',(v->>'p_starts_on')::date,(v->>'p_ends_on')::date,nullif(v->>'p_starts_at','')::time,nullif(v->>'p_ends_at','')::time,nullif(v->>'p_class_id','')::uuid,nullif(v->>'p_teacher_id','')::uuid,v->>'p_note',v->>'p_contact_name',v->>'p_contact_phone',v->>'p_location',v->>'p_status');
 update public.academic_calendar_events set reminder_enabled=coalesce(p_reminder_enabled,false), reminder_recipient_ids=case when v ? 'p_reminder_recipient_ids' then array(select value::uuid from jsonb_array_elements_text(v->'p_reminder_recipient_ids')) else reminder_recipient_ids end where academic_calendar_events.id=v_id;
 return v_id;end $function$
;

CREATE OR REPLACE FUNCTION public.staff_save_special_with_reminder(p_values jsonb, p_reminder_enabled boolean)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid;v jsonb:=p_values;begin
 if not public.is_staff() then raise exception '저장 권한이 없습니다.';end if;
 v_id:=public.staff_save_teacher_special_lesson(nullif(v->>'p_id','')::uuid,nullif(v->>'p_teacher_id','')::uuid,(v->>'p_date')::date,(v->>'p_start_time')::time,(v->>'p_end_time')::time,v->>'p_kind',v->>'p_room',v->>'p_note',array(select value::uuid from jsonb_array_elements_text(v->'p_student_ids')),nullif(v->>'p_subject_id','')::uuid);
 update public.teacher_special_lessons set reminder_enabled=coalesce(p_reminder_enabled,false), reminder_recipient_ids=case when v ? 'p_reminder_recipient_ids' then array(select value::uuid from jsonb_array_elements_text(v->'p_reminder_recipient_ids')) else reminder_recipient_ids end where teacher_special_lessons.id=v_id;
 return v_id;end $function$
;

CREATE OR REPLACE FUNCTION public.staff_teacher_special_lessons(p_teacher_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role public.user_role; v_teacher uuid;
begin
  if not public.is_staff() then raise exception '교직원만 확인할 수 있습니다.'; end if;
  v_role:=public.current_user_role();
  v_teacher:=case when v_role='admin' then p_teacher_id else auth.uid() end;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'reminderRecipientIds',coalesce(l.reminder_recipient_ids,array_remove(array[l.teacher_profile_id],null)),'reminderEnabled',l.reminder_enabled,'id',l.id,'date',l.lesson_date,'startTime',l.starts_at,'endTime',l.ends_at,'kind',l.kind,
    'subjectId',l.subject_id,'subject',s.name,'mainSubject',s.main_subject,
    'room',l.room,'note',l.note,'teacherName',p.display_name,'teacherId',l.teacher_profile_id,
    'students',coalesce((select jsonb_agg(jsonb_build_object(
      'id',st.id,'name',st.name,'school',st.school,'grade',st.grade,
      'attendanceStatus',a.attendance_status
    ) order by st.name)
      from public.teacher_special_lesson_students a
      join public.students st on st.id=a.student_id
      where a.session_id=l.id),'[]'::jsonb)
  ) order by l.lesson_date,l.starts_at)
  from public.teacher_special_lessons l
  join public.profiles p on p.id=l.teacher_profile_id
  left join public.academy_subjects s on s.id=l.subject_id
  where v_teacher is null or l.teacher_profile_id=v_teacher),'[]'::jsonb);
end $function$
;
