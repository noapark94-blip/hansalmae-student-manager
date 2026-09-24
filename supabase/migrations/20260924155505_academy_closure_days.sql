-- Explicit academy closures. Existing general calendar events are never reinterpreted.
create table public.academy_closures(
 id uuid primary key default gen_random_uuid(), starts_on date not null, ends_on date not null,
 reason text not null check(char_length(trim(reason)) between 1 and 120),
 regular boolean not null default true, correction boolean not null default true,
 updated_at timestamptz not null default clock_timestamp(), updated_by uuid references public.profiles(id) on delete set null,
 check(ends_on>=starts_on and ends_on-starts_on<=366), check(regular or correction)
);
alter table public.academy_closures enable row level security;
revoke all on public.academy_closures from public,anon,authenticated;
create table public.academy_day_openings(
 kind text not null check(kind in ('regular','correction')), entity_id uuid not null,
 student_id uuid not null references public.students(id) on delete cascade, lesson_date date not null,
 updated_by uuid references public.profiles(id) on delete set null, updated_at timestamptz not null default clock_timestamp(),
 primary key(kind,entity_id,student_id,lesson_date)
);
alter table public.academy_day_openings enable row level security;
revoke all on public.academy_day_openings from public,anon,authenticated;
create index academy_day_openings_student_date_idx on public.academy_day_openings(student_id,lesson_date);
create index academy_day_openings_actor_idx on public.academy_day_openings(updated_by);
create index academy_closures_actor_idx on public.academy_closures(updated_by);

create function public.internal_academy_closure(p_date date,p_kind text) returns text
language sql stable security invoker set search_path=public as $$
 select string_agg(reason,' · ' order by starts_on,id) from public.academy_closures
 where p_date between starts_on and ends_on and case p_kind when 'regular' then regular when 'correction' then correction else false end
$$;
create or replace function public.internal_class_student_excluded(p_student uuid,p_class uuid,p_date date) returns boolean
language sql stable security invoker set search_path=public as $$
 select exists(select 1 from public.class_lesson_participation where class_id=p_class and lesson_date=p_date and student_id=p_student and excluded)
 or (public.internal_academy_closure(p_date,'regular') is not null and not exists(
 select 1 from public.academy_day_openings where kind='regular' and entity_id=p_class and student_id=p_student and lesson_date=p_date))
$$;
create function public.internal_correction_closed(p_assignment uuid,p_date date) returns boolean
language sql stable security invoker set search_path=public as $$
 select public.internal_academy_closure(p_date,'correction') is not null
 and not exists(select 1 from public.academy_day_openings where kind='correction' and entity_id=p_assignment and lesson_date=p_date)
 and not exists(select 1 from public.correction_assignments where id=p_assignment and not active and valid_until is not null and (timezone('Asia/Seoul',created_at))::date>valid_until)
 and not exists(select 1 from public.correction_schedule_exceptions where assignment_id=p_assignment and target_date=p_date and kind in ('move','extra'))
$$;
create or replace function public.internal_class_participation_version(p_class uuid,p_date date) returns text
language sql stable security invoker set search_path=public as $$
 select md5(jsonb_build_array(
 (select coalesce(jsonb_agg(jsonb_build_array(student_id,excluded,reason,updated_at) order by student_id),'[]') from public.class_lesson_participation where class_id=p_class and lesson_date=p_date),
 (select coalesce(jsonb_agg(jsonb_build_array(id,updated_at) order by id),'[]') from public.academy_closures where regular and p_date between starts_on and ends_on),
 (select coalesce(jsonb_agg(jsonb_build_array(student_id,updated_at) order by student_id),'[]') from public.academy_day_openings where kind='regular' and entity_id=p_class and lesson_date=p_date))::text)
$$;
revoke all on function public.internal_academy_closure(date,text),public.internal_correction_closed(uuid,date) from public,anon,authenticated;

create function public.staff_academy_closures(p_from date,p_to date) returns jsonb
language plpgsql stable security definer set search_path=public as $$
begin
 if auth.uid() is null or not coalesce(public.is_staff(),false) then raise exception '교직원만 확인할 수 있습니다.'; end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>732 then raise exception '기간을 확인해 주세요.'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',id,'startsOn',starts_on,'endsOn',ends_on,'reason',reason,'regular',regular,'correction',correction,'version',updated_at::text) order by starts_on,id) from public.academy_closures where starts_on<=p_to and ends_on>=p_from),'[]');
end $$;
create function public.admin_save_academy_closure(p_id uuid,p_from date,p_to date,p_reason text,p_regular boolean,p_correction boolean,p_version text default null,p_confirm boolean default false,p_delete boolean default false) returns jsonb
language plpgsql security definer set search_path=public as $$
declare old public.academy_closures; nregular integer; ncorrection integer; rid uuid; r record;
begin
 if auth.uid() is null or public.current_user_role() is distinct from 'admin' then raise exception '관리자만 학원 휴강을 설정할 수 있습니다.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('academy-closure',0));
 if p_id is not null then
  select * into old from public.academy_closures where id=p_id for update;
  if not found or old.updated_at::text is distinct from p_version then raise exception '휴강 일정이 변경됐습니다. 새로고침 후 다시 시도해 주세요.'; end if;
 end if;
 if p_delete then
  if p_id is null then raise exception '휴강 일정을 선택해 주세요.'; end if;
  delete from public.academy_closures where id=p_id;
  return jsonb_build_object('saved',true);
 end if;
 if p_from is null or p_to is null or p_to<p_from or p_to-p_from>366 or not coalesce(p_regular or p_correction,false) or char_length(trim(coalesce(p_reason,''))) not between 1 and 120 then raise exception '휴강 기간·사유·적용 대상을 확인해 주세요.'; end if;
 select count(*) into nregular from public.lessons l where p_regular and l.lesson_date between p_from and p_to and l.status<>'cancelled' and (l.status='completed' or exists(select 1 from public.attendance where lesson_id=l.id) or exists(select 1 from public.lesson_exam_results where lesson_id=l.id) or exists(select 1 from public.lesson_homework_results where lesson_id=l.id) or nullif(trim(l.lesson_content),'') is not null or nullif(trim(l.homework_content),'') is not null or nullif(trim(l.exam_content),'') is not null or l.revision_draft is not null);
 select count(*) into ncorrection from public.correction_reports where p_correction and correction_date between p_from and p_to;
 if not p_confirm then return jsonb_build_object('saved',false,'regularRecords',nregular,'correctionRecords',ncorrection); end if;
 -- Preserve existing saved lessons explicitly, without changing any attendance or report.
 insert into public.academy_day_openings(kind,entity_id,student_id,lesson_date,updated_by)
 select distinct 'regular',l.class_id,s.id,l.lesson_date,auth.uid() from public.lessons l join public.students s on public.student_attends_class_on(s.id,l.class_id,l.lesson_date)
 where not public.internal_class_student_excluded(s.id,l.class_id,l.lesson_date) and p_regular and l.lesson_date between p_from and p_to and l.status<>'cancelled' and (l.status='completed' or exists(select 1 from public.attendance where lesson_id=l.id) or exists(select 1 from public.lesson_exam_results where lesson_id=l.id) or exists(select 1 from public.lesson_homework_results where lesson_id=l.id) or nullif(trim(l.lesson_content),'') is not null or nullif(trim(l.homework_content),'') is not null or nullif(trim(l.exam_content),'') is not null or l.revision_draft is not null)
 on conflict do nothing;
 insert into public.academy_day_openings(kind,entity_id,student_id,lesson_date,updated_by)
 select distinct 'correction',assignment_id,student_id,correction_date,auth.uid() from public.correction_reports where not public.internal_correction_closed(assignment_id,correction_date) and p_correction and correction_date between p_from and p_to on conflict do nothing;
 insert into public.academy_closures(id,starts_on,ends_on,reason,regular,correction,updated_by)
 values(coalesce(p_id,gen_random_uuid()),p_from,p_to,trim(p_reason),p_regular,p_correction,auth.uid())
 on conflict(id) do update set starts_on=excluded.starts_on,ends_on=excluded.ends_on,reason=excluded.reason,regular=excluded.regular,correction=excluded.correction,updated_by=auth.uid(),updated_at=clock_timestamp() returning id into rid;
 return jsonb_build_object('saved',true,'id',rid,'regularRecords',nregular,'correctionRecords',ncorrection);
end $$;
revoke all on function public.staff_academy_closures(date,date),public.admin_save_academy_closure(uuid,date,date,text,boolean,boolean,text,boolean,boolean) from public,anon;
grant execute on function public.staff_academy_closures(date,date),public.admin_save_academy_closure(uuid,date,date,text,boolean,boolean,text,boolean,boolean) to authenticated;

create function public.staff_open_correction_day(p_assignment uuid,p_date date) returns void
language plpgsql security definer set search_path=public as $$
declare a public.correction_assignments;
begin
 if auth.uid() is null or not coalesce(public.is_staff(),false) then raise exception '교직원만 첨삭을 진행할 수 있습니다.'; end if;
 select * into a from public.correction_assignments where id=p_assignment;
 if not found then raise exception '첨삭 배정을 찾을 수 없습니다.'; end if;
 if p_date is null or p_date<a.valid_from or (a.valid_until is not null and p_date>a.valid_until) then raise exception '첨삭 날짜를 확인해 주세요.'; end if;
 perform pg_advisory_xact_lock_shared(hashtextextended('academy-closure',0));
 insert into public.academy_day_openings(kind,entity_id,student_id,lesson_date,updated_by) values('correction',a.id,a.student_id,p_date,auth.uid()) on conflict do nothing;
end $$;
revoke all on function public.staff_open_correction_day(uuid,date) from public,anon;
grant execute on function public.staff_open_correction_day(uuid,date) to authenticated;

create function public.guard_academy_closure_write() returns trigger
language plpgsql security definer set search_path=public as $$
declare c uuid; d date;
begin
 perform pg_advisory_xact_lock_shared(hashtextextended('academy-closure',0));
 if tg_table_name='correction_reports' then
  if public.internal_correction_closed(new.assignment_id,new.correction_date) then raise exception '학원 휴강일입니다. 오늘 첨삭 진행을 먼저 선택해 주세요.'; end if;
 else
  select class_id,lesson_date into c,d from public.lessons where id=new.lesson_id;
  if public.internal_class_student_excluded(new.student_id,c,d) then raise exception '휴강 또는 수업 제외 학생입니다. 오늘 수업 대상으로 먼저 포함해 주세요.'; end if;
 end if;
 return new;
end $$;
revoke all on function public.guard_academy_closure_write() from public,anon,authenticated;
create trigger academy_closure_guard before insert or update on public.correction_reports for each row execute function public.guard_academy_closure_write();
create trigger academy_closure_guard before insert or update on public.attendance for each row execute function public.guard_academy_closure_write();
-- Existing class save functions deliberately preserve excluded exam/homework rows; do not put write triggers on those tables.
create view public.internal_open_correction_reports with(security_invoker=true) as select * from public.correction_reports where not public.internal_correction_closed(assignment_id,correction_date);
revoke all on public.internal_open_correction_reports from public,anon,authenticated;
create function public.staff_open_correction_days(p_assignments uuid[],p_date date) returns void
language plpgsql security definer set search_path=public as $$
declare aid uuid;
begin
 if auth.uid() is null or not coalesce(public.is_staff(),false) then raise exception '교직원만 첨삭을 진행할 수 있습니다.'; end if;
 if cardinality(p_assignments) is null or cardinality(p_assignments) not between 1 and 300 then raise exception '진행할 첨삭 학생을 선택해 주세요.'; end if;
 foreach aid in array p_assignments loop perform public.staff_open_correction_day(aid,p_date); end loop;
end $$;
revoke all on function public.staff_open_correction_days(uuid[],date) from public,anon;
grant execute on function public.staff_open_correction_days(uuid[],date) to authenticated;

create function public.notify_academy_closure_change() returns trigger language plpgsql security definer set search_path=public as $$
declare eid uuid;
begin
 if tg_table_name='academy_closures' then eid:=coalesce(new.id,old.id); else eid:=coalesce(new.entity_id,old.entity_id); end if;
 insert into public.staff_live_signals(key,topic,entity_id) values('academy-closures','closures',eid) on conflict(key) do update set entity_id=excluded.entity_id,changed_at=clock_timestamp();
 return null;
end $$;
revoke all on function public.notify_academy_closure_change() from public,anon,authenticated;
create trigger academy_closure_changed after insert or update or delete on public.academy_closures for each row execute function public.notify_academy_closure_change();
create trigger academy_opening_changed after insert or update or delete on public.academy_day_openings for each row execute function public.notify_academy_closure_change();


CREATE OR REPLACE FUNCTION public.family_correction_exam_progress(p_student_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare role_now public.user_role; allowed_id uuid;
begin
  role_now:=public.current_user_role();
  if role_now='student' then
    select id into allowed_id from public.students where profile_id=auth.uid() and id=p_student_id;
  elsif role_now='guardian' then
    select s.id into allowed_id
    from public.guardians g
    join public.student_guardians sg on sg.guardian_id=g.id
    join public.students s on s.id=sg.student_id
    where g.profile_id=auth.uid() and s.id=p_student_id;
  end if;
  if allowed_id is null then
    raise exception '연결된 학생의 첨삭 성적만 확인할 수 있습니다.';
  end if;
  return coalesce((
    select jsonb_agg(to_jsonb(q) order by q."lessonDate" desc,q.id desc)
    from (
      select
        r.id,
        r.correction_date as "lessonDate",
        (r.subject||' 첨삭')::text as "className",
        r.subject,
        r.subject as "mainSubject",
        case
          when coalesce(r.exam_range,'') like '[종류]%'
          then coalesce(nullif(trim(replace(split_part(r.exam_range,E'\n',1),'[종류]','')),''),'첨삭 시험')
          else '첨삭 시험'
        end as "examType",
        r.exam_title as "examTitle",
        'correction'::text as "itemType",
        r.exam_score as score,
        coalesce(nullif(r.exam_max_score,0),100) as "maxScore",
        case
          when r.exam_score is null then null
          else round(r.exam_score*100.0/coalesce(nullif(r.exam_max_score,0),100),1)
        end as percent
      from public.internal_open_correction_reports r
      where r.student_id=allowed_id and r.published and r.exam_score is not null
      order by r.correction_date desc,r.created_at desc
      limit 80
    ) q
  ),'[]'::jsonb);
end $function$

;

CREATE OR REPLACE FUNCTION public.family_previous_homework(p_student_id uuid, p_record_id uuid, p_kind text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare selected_id uuid; current_row record; result text;
begin
 selected_id := public.internal_family_student_id(p_student_id);
 if selected_id is null then raise exception '연결된 학생의 기록만 확인할 수 있습니다.'; end if;
 if p_kind='correction' then
  select r.* into current_row from public.internal_open_correction_reports r where r.id=p_record_id and r.student_id=selected_id and r.published and r.correction_date<=current_date;
  if not found then raise exception '공개된 첨삭 기록만 확인할 수 있습니다.'; end if;
  select r.homework_instruction into result from public.internal_open_correction_reports r
  where r.student_id=selected_id and r.published and r.subject=current_row.subject
   and (r.correction_date,r.start_time)<(current_row.correction_date,current_row.start_time)
   and nullif(trim(r.homework_instruction),'') is not null
  order by r.correction_date desc,r.start_time desc,r.id desc limit 1;
 elsif p_kind='lesson' then
  select l.* into current_row from public.lessons l where l.id=p_record_id and l.status='completed' and l.lesson_date<=current_date
   and exists(select 1 from public.internal_participating_attendance a where a.lesson_id=l.id and a.student_id=selected_id);
  if found then
   select coalesce(hr.assigned_homework,l.homework_content,'') into result
   from public.lessons l left join public.internal_participating_homework hr on hr.lesson_id=l.id and hr.student_id=selected_id
   where l.class_id=current_row.class_id and l.status='completed' and l.starts_at<current_row.starts_at and l.lesson_date<=current_date
    and exists(select 1 from public.internal_participating_attendance a where a.lesson_id=l.id and a.student_id=selected_id)
    and nullif(trim(coalesce(hr.assigned_homework,l.homework_content,'')),'') is not null
   order by l.starts_at desc,l.id desc limit 1;
  else
   select l.* into current_row from public.teacher_special_lessons l where l.id=p_record_id and l.status='completed' and l.lesson_date<=current_date
    and exists(select 1 from public.teacher_special_lesson_students a where a.session_id=l.id and a.student_id=selected_id);
   if not found then raise exception '공개된 수업 기록만 확인할 수 있습니다.'; end if;
   select a.assigned_homework into result
   from public.teacher_special_lessons l join public.teacher_special_lesson_students a on a.session_id=l.id and a.student_id=selected_id
   where l.status='completed' and public.internal_special_student_kind(l.id,selected_id)=public.internal_special_student_kind(current_row.id,selected_id) and l.subject_id is not distinct from current_row.subject_id
    and l.teacher_profile_id is not distinct from current_row.teacher_profile_id
    and (l.lesson_date,l.starts_at)<(current_row.lesson_date,current_row.starts_at)
    and nullif(trim(a.assigned_homework),'') is not null
   order by l.lesson_date desc,l.starts_at desc,l.id desc limit 1;
  end if;
 else raise exception '지원하지 않는 기록 종류입니다.';
 end if;
 return coalesce(trim(result),'');
end $function$

;

CREATE OR REPLACE FUNCTION public.staff_student_attendance_makeup_history(p_student_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
        from public.internal_participating_attendance a
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
        from public.internal_open_correction_reports r
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
        join public.internal_participating_attendance a on a.id = ms.attendance_id
        join public.lessons l on l.id = a.lesson_id
        join public.classes c on c.id = l.class_id
        join public.profiles p on p.id = ms.teacher_profile_id
        where a.student_id = p_student_id

        union all

        select
          ('special:' || sl.id::text) as id,
          case when public.internal_special_student_kind(sl.id,p_student_id) = 'makeup' then '개별 보강' else '추가수업' end as "className",
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
          case when public.internal_special_student_kind(sl.id,p_student_id) = 'makeup' then 'individual_makeup' else 'additional' end as "recordKind"
        from public.teacher_special_lessons sl
        join public.teacher_special_lesson_students ss on ss.session_id = sl.id
        join public.profiles p on p.id = sl.teacher_profile_id
        where ss.student_id = p_student_id
      ) q
    ), '[]'::jsonb)
  );
end
$function$

;

CREATE OR REPLACE FUNCTION public.family_summary_snapshot(p_student_id uuid, p_start_date date, p_end_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare selected_id uuid; lesson_rows jsonb; correction_rows jsonb; context_row jsonb;
begin
  selected_id := public.internal_family_student_id(p_student_id);
  if p_start_date is null or p_end_date is null or p_end_date < p_start_date or p_end_date-p_start_date > 31 then
    raise exception '조회 기간은 최대 32일이며 시작일과 종료일이 필요합니다.';
  end if;
  context_row := public.family_student_context(selected_id);
  if selected_id is null then
    return jsonb_build_object('dashboard',context_row,'lessons','[]'::jsonb,'corrections','[]'::jsonb);
  end if;
  select coalesce(jsonb_agg(item order by lesson_date desc,starts_at desc),'[]'::jsonb) into lesson_rows
  from (
    select jsonb_build_object(
      'lessonId',l.id,'lessonDate',to_char(l.lesson_date,'YYYY-MM-DD'),'startsAt',l.starts_at,'classId',c.id,'className',c.name,'subject',c.subject,'room',coalesce(l.room,c.room),'teacherName',coalesce(tp.display_name,'담당 선생님'),
      'lessonContent',coalesce(nullif(trim(hr.lesson_content),''),l.lesson_content,''),'classNotice',coalesce(n.content,''),'homeworkContent',coalesce(hr.assigned_homework,l.homework_content,''),'examContent',coalesce(l.exam_content,''),
      'attendance',case when a.id is null then null else jsonb_build_object('status',a.status,'lateMinutes',a.late_minutes,'absenceReason',coalesce(a.absence_reason,''),'note',coalesce(a.note,'')) end,
      'homeworkResult',case when hr.id is null then null else jsonb_build_object('status',coalesce(hr.inspection_status,hr.status,''),'note',coalesce(hr.inspection_note,hr.note,'')) end,
      'exams',coalesce((select jsonb_agg(jsonb_build_object('id',er.id,'examType',coalesce(er.exam_type,''),'examTitle',coalesce(er.exam_title,''),'score',er.score,'maxScore',coalesce(er.max_score,100),'percent',case when er.score is null or coalesce(er.max_score,0)<=0 then null else round(er.score/er.max_score*100,1) end,'evaluation',coalesce(er.evaluation,''),'feedback',coalesce(er.feedback,'')) order by er.created_at,er.id) from public.internal_participating_exams er where er.lesson_id=l.id and er.student_id=selected_id and er.id=public.internal_class_current_exam_id(l.id,selected_id) and (er.score is not null or nullif(trim(concat_ws(' ',er.exam_type,er.exam_title,er.evaluation,er.feedback)),'') is not null)),'[]'::jsonb)
    ) item,l.lesson_date,l.starts_at::text starts_at
    from public.lessons l join public.classes c on c.id=l.class_id
    left join public.profiles tp on tp.id=l.teacher_profile_id left join public.internal_participating_attendance a on a.lesson_id=l.id and a.student_id=selected_id left join public.internal_participating_homework hr on hr.lesson_id=l.id and hr.student_id=selected_id
    left join public.class_daily_notices n on n.class_id=l.class_id and n.notice_date=l.lesson_date
    where l.status='completed' and a.id is not null
      and l.lesson_date between p_start_date and least(p_end_date,current_date)
      union all
      select jsonb_build_object(
        'lessonId',l.id,'lessonDate',to_char(l.lesson_date,'YYYY-MM-DD'),
        'startsAt',to_char(l.lesson_date,'YYYY-MM-DD')||'T'||l.starts_at::text||'+09:00',
        'classId',l.id,'className',case when public.internal_special_student_kind(l.id,selected_id)='makeup' then '개별 보강' else '추가수업' end,
        'subject',case when public.internal_special_student_kind(l.id,selected_id)='makeup' then '보강' else '추가수업' end,
        'mainSubject',coalesce(sub.name,''),
        'room',l.room,'teacherName',coalesce(p.display_name,'담당 선생님'),
        'lessonContent',coalesce(a.lesson_content,''),'homeworkContent',coalesce(a.assigned_homework,''),
        'examContent','',
        'attendance',case when a.attendance_status is null then null else jsonb_build_object(
          'status',a.attendance_status,'lateMinutes',a.late_minutes,
          'absenceReason',coalesce(a.absence_reason,''),'note','') end,
        'homeworkResult',case when a.inspection_status is null then null else jsonb_build_object(
          'status',a.inspection_status,'note',coalesce(a.inspection_note,'')) end,
        'exams',coalesce((select jsonb_agg(jsonb_build_object(
          'id',e.id,'examType',coalesce(e.exam_type,''),'examTitle',coalesce(e.exam_title,''),
          'score',e.score,'maxScore',coalesce(e.max_score,100),
          'percent',case when e.score is null or coalesce(e.max_score,0)<=0 then null else round(e.score/e.max_score*100,1) end,
          'evaluation',coalesce(e.evaluation,''),'feedback',coalesce(e.evaluation,'')
        )) from public.teacher_special_lesson_exam_results e
          where e.session_id=l.id and e.student_id=selected_id),'[]'::jsonb)
      ) item,l.lesson_date,l.starts_at::text starts_at
      from public.teacher_special_lessons l
      join public.teacher_special_lesson_students a on a.session_id=l.id and a.student_id=selected_id
      left join public.academy_subjects sub on sub.id=l.subject_id
      left join public.profiles p on p.id=l.teacher_profile_id
      where l.status='completed' and l.lesson_date between p_start_date and least(p_end_date,current_date)
  ) reports;
  select coalesce((select jsonb_agg(to_jsonb(q) order by q."correctionDate" desc,q."startTime" desc) from (select r.id,r.correction_date as "correctionDate",r.start_time as "startTime",r.end_time as "endTime",r.subject,r.attendance_status as "attendanceStatus",r.late_minutes as "lateMinutes",r.exam_title as "examTitle",r.exam_range as "examRange",r.exam_score as "examScore",r.exam_max_score as "examMaxScore",r.evaluation,r.homework_instruction as "homeworkInstruction",r.homework_status as "homeworkStatus",r.homework_note as "homeworkNote",r.correction_content as "correctionContent",r.correction_task_status as "correctionTaskStatus",coalesce(r.correction_task_feedback,'') as "correctionTaskFeedback",r.assistant_feedback as "assistantFeedback",r.next_preparation as "nextPreparation",r.recorded_by_name as "recordedByName" from public.internal_open_correction_reports r where r.student_id=selected_id and r.published and r.correction_date between p_start_date and least(p_end_date,current_date) order by r.correction_date desc,r.start_time desc) q),'[]'::jsonb) into correction_rows;
  return jsonb_build_object('dashboard',context_row,'lessons',lesson_rows,'corrections',correction_rows);
end $function$

;

CREATE OR REPLACE FUNCTION public.family_correction_reports(p_student_id uuid, p_limit integer DEFAULT 20)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare role_now public.user_role; allowed_id uuid;
begin
  role_now:=public.current_user_role();
  if role_now='student' then select id into allowed_id from public.students where profile_id=auth.uid() and id=p_student_id;
  elsif role_now='guardian' then select s.id into allowed_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() and s.id=p_student_id; end if;
  if allowed_id is null then raise exception '연결된 학생의 첨삭 리포트만 확인할 수 있습니다.'; end if;
  return coalesce((select jsonb_agg(to_jsonb(q) order by q."correctionDate" desc,q."startTime" desc) from (select r.id,r.correction_date as "correctionDate",r.start_time as "startTime",r.end_time as "endTime",r.subject,r.attendance_status as "attendanceStatus",r.late_minutes as "lateMinutes",r.exam_title as "examTitle",r.exam_range as "examRange",r.exam_score as "examScore",r.exam_max_score as "examMaxScore",r.evaluation,r.homework_instruction as "homeworkInstruction",r.homework_status as "homeworkStatus",r.homework_note as "homeworkNote",r.correction_content as "correctionContent",r.correction_task_status as "correctionTaskStatus",coalesce(r.correction_task_feedback,'') as "correctionTaskFeedback",r.assistant_feedback as "assistantFeedback",r.next_preparation as "nextPreparation",r.recorded_by_name as "recordedByName" from public.internal_open_correction_reports r where r.student_id=allowed_id and r.published order by r.correction_date desc,r.start_time desc limit greatest(1,least(coalesce(p_limit,20),50))) q),'[]'::jsonb);
end $function$

;

CREATE OR REPLACE FUNCTION public.staff_learning_report_source(p_student_id uuid, p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare base_rows jsonb; result jsonb;
begin
  if p_from is null or p_to is null or p_to<p_from or p_to-p_from>31 then raise exception '조회 기간을 확인해 주세요.'; end if;
  if not (public.can_staff_report_student(p_student_id) or public.can_send_alimtalk()) then raise exception '담당 학생의 리포트만 만들 수 있습니다.'; end if;
  base_rows:=public.specialized_completed_history_range(p_student_id,p_from,p_to);
  select coalesce(jsonb_agg(item order by report_date,starts_at),'[]'::jsonb) into result from (
    select jsonb_set(entry.item,'{source}',to_jsonb(case
      when entry.item->>'source'='additional' then 'extra'
      when entry.item->>'source' in ('makeup','extra') then entry.item->>'source'
      when exists(select 1 from public.class_makeup_attendees ma where ma.class_id=(entry.item->>'classId')::uuid and ma.student_id=p_student_id and ma.attendance_date=(entry.item->>'lessonDate')::date) then 'makeup'
      else 'regular' end)) item,
      (entry.item->>'lessonDate')::date report_date,entry.item->>'startsAt' starts_at
    from jsonb_array_elements(coalesce(base_rows,'[]'::jsonb)) entry(item)
    where (entry.item->>'lessonDate')::date between p_from and p_to
    union all
    select jsonb_build_object(
      'lessonId',r.id,'lessonDate',to_char(r.correction_date,'YYYY-MM-DD'),
      'startsAt',to_char(r.correction_date,'YYYY-MM-DD')||'T'||r.start_time::text||'+09:00',
      'classId',r.assignment_id,'className','첨삭','subject',r.subject,'source','correction','room',null,
      'teacherName',coalesce(r.recorded_by_name,'담당 선생님'),'lessonContent',coalesce(r.correction_content,''),
      'homeworkContent',coalesce(r.next_preparation,r.homework_instruction,''),'examContent',coalesce(r.exam_range,''),
      'correctionTaskStatus',r.correction_task_status,'correctionTaskFeedback',coalesce(r.correction_task_feedback,''),
      'attendance',jsonb_build_object('status',r.attendance_status,'lateMinutes',r.late_minutes,'absenceReason','','note',coalesce(r.assistant_feedback,'')),
      'homeworkResult',case when r.homework_status is null then null else jsonb_build_object('status',r.homework_status,'note',coalesce(r.homework_note,'')) end,
      'exams',case when r.exam_title is null and r.exam_score is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object(
        'id',r.id,
        'examType',case when coalesce(r.exam_range,'') like '[종류]%' then coalesce(nullif(trim(replace(split_part(r.exam_range,E'\n',1),'[종류]','')),''),'첨삭 평가') else '첨삭 평가' end,
        'examTitle',coalesce(r.exam_title,''),'score',r.exam_score,'maxScore',coalesce(r.exam_max_score,100),
        'percent',case when r.exam_score is null or coalesce(r.exam_max_score,0)<=0 then null else round(r.exam_score/r.exam_max_score*100,1) end,
        'evaluation',coalesce(r.evaluation,''),'feedback',coalesce(r.teacher_instruction,''))) end
    ) item,r.correction_date report_date,r.start_time::text starts_at
    from public.internal_open_correction_reports r join public.correction_assignments ca on ca.id=r.assignment_id
    where r.student_id=p_student_id and r.correction_date between p_from and p_to and r.published
      and (public.can_send_alimtalk() or ca.teacher_profile_id=auth.uid())
  ) rows;
  return result;
end $function$

;

CREATE OR REPLACE FUNCTION public.staff_correction_report_read_status(p_date date)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with published as (
  select r.id report_id,r.student_id from public.internal_open_correction_reports r where r.correction_date=p_date and r.published
), students_for_date as (
  select distinct p.student_id,s.name student_name,s.school,s.grade from published p join public.students s on s.id=p.student_id
), status_rows as (
  select sfd.*,
    (select count(distinct g.profile_id)::integer from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id where sg.student_id=sfd.student_id and g.profile_id is not null) guardian_count,
    (select count(*)::integer from published p where p.student_id=sfd.student_id) report_count,
    (select count(distinct p.report_id)::integer from published p join public.correction_report_reads rr on rr.report_id=p.report_id and rr.student_id=sfd.student_id join public.guardians g on g.profile_id=rr.viewer_profile_id join public.student_guardians sg on sg.guardian_id=g.id and sg.student_id=sfd.student_id where p.student_id=sfd.student_id) read_report_count,
    (select max(rr.viewed_at) from published p join public.correction_report_reads rr on rr.report_id=p.report_id and rr.student_id=sfd.student_id join public.guardians g on g.profile_id=rr.viewer_profile_id join public.student_guardians sg on sg.guardian_id=g.id and sg.student_id=sfd.student_id where p.student_id=sfd.student_id) viewed_at
  from students_for_date sfd
), normalized as (
  select *,case when guardian_count=0 then 'unlinked' when read_report_count>=report_count then 'confirmed' else 'unconfirmed' end status from status_rows
)
select case when public.is_staff() then jsonb_build_object(
  'reportAvailable',exists(select 1 from published),'totalStudents',(select count(*) from normalized),
  'linkedStudents',(select count(*) from normalized where guardian_count>0),'confirmedStudents',(select count(*) from normalized where status='confirmed'),
  'unconfirmedStudents',(select count(*) from normalized where status='unconfirmed'),'unlinkedStudents',(select count(*) from normalized where status='unlinked'),
  'students',coalesce((select jsonb_agg(jsonb_build_object('studentId',student_id,'studentName',student_name,'school',school,'grade',grade,'guardianCount',guardian_count,'readCount',read_report_count,'status',status,'viewedAt',viewed_at) order by student_name) from normalized),'[]'::jsonb)
) else null end;
$function$

;

CREATE OR REPLACE FUNCTION public.staff_record_worklist(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
      exists(select 1 from public.lessons l join public.internal_participating_attendance at on at.lesson_id=l.id and at.student_id=e.student_id where l.class_id=cs.class_id and l.lesson_date=d.occurrence_date and l.status='completed' and at.status::text in ('present','late','absent','excused')) completed
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
      exists(select 1 from public.lessons l join public.internal_participating_attendance at on at.lesson_id=l.id and at.student_id=e.student_id where l.class_id=x.class_id and l.lesson_date=x.replacement_date and l.status='completed' and at.status::text in ('present','late','absent','excused'))
    from public.schedule_exceptions x join public.class_schedules cs on cs.class_id=x.class_id and cs.weekday=extract(isodow from x.original_date)::smallint
    join public.classes c on c.id=x.class_id and c.active join public.enrollments e on e.class_id=c.id and e.status='active'
      and e.started_on<=x.replacement_date and (e.ended_on is null or e.ended_on>=x.replacement_date)
    join public.students s on s.id=e.student_id and s.status in ('active','재원')
    where (cs.valid_from is null or cs.valid_from<=x.original_date) and (cs.valid_until is null or cs.valid_until>=x.original_date) and public.student_attends_class_on(e.student_id,x.class_id,x.original_date) and x.kind in ('changed','makeup') and x.replacement_date between p_from and p_to
  ),
  class_makeups as (
    select distinct m.student_id,'class-makeup:'||m.class_id||':'||m.attendance_date expected_key,'보강수업',c.name,m.attendance_date,cs.start_time,
      exists(select 1 from public.lessons l join public.internal_participating_attendance at on at.lesson_id=l.id and at.student_id=m.student_id where l.class_id=m.class_id and l.lesson_date=m.attendance_date and l.status='completed' and at.status::text in ('present','late','absent','excused'))
    from public.class_makeup_attendees m join public.classes c on c.id=m.class_id
    left join public.class_schedules cs on cs.class_id=m.class_id and cs.weekday=extract(isodow from m.attendance_date)::smallint
    join public.students s on s.id=m.student_id and s.status in ('active','재원') where m.attendance_date between p_from and p_to
  ),
  special_lessons as (
    select a.student_id,'special:'||l.id expected_key,case when public.internal_special_student_kind(l.id,a.student_id)='makeup' then '개별 보강' else '추가수업' end,
      coalesce(sub.name,case when public.internal_special_student_kind(l.id,a.student_id)='makeup' then '보강' else '추가수업' end),l.lesson_date,l.starts_at,
      l.status='completed' and a.attendance_status is not null
    from public.teacher_special_lessons l join public.teacher_special_lesson_students a on a.session_id=l.id
    join public.students s on s.id=a.student_id and s.status in ('active','재원') left join public.academy_subjects sub on sub.id=l.subject_id
    where l.lesson_date between p_from and p_to and l.status<>'cancelled'
  ),
  correction_fixed as (
    select a.student_id,'correction:'||a.id||':'||d.occurrence_date||':'||a.start_time expected_key,'첨삭수업',a.subject||' 첨삭',d.occurrence_date,a.start_time,
      exists(select 1 from public.internal_open_correction_reports r where r.assignment_id=a.id and r.student_id=a.student_id and r.correction_date=d.occurrence_date and r.start_time=a.start_time and r.published and r.attendance_status<>'scheduled')
    from days d join public.correction_assignments a on a.active and a.weekday=extract(isodow from d.occurrence_date)::smallint
      and (a.valid_from is null or a.valid_from<=d.occurrence_date) and (a.valid_until is null or a.valid_until>=d.occurrence_date)
    join public.students s on s.id=a.student_id and s.status in ('active','재원')
    where not exists(select 1 from public.correction_schedule_exceptions x where x.assignment_id=a.id and x.original_date=d.occurrence_date and x.kind in ('move','cancel'))
  ),
  correction_changes as (
    select a.student_id,'correction:'||a.id||':'||x.target_date||':'||x.target_start_time expected_key,'첨삭수업',a.subject||case when x.kind='extra' then ' 추가 첨삭' else ' 첨삭' end,x.target_date,x.target_start_time,
      exists(select 1 from public.internal_open_correction_reports r where r.assignment_id=a.id and r.student_id=a.student_id and r.correction_date=x.target_date and r.start_time=x.target_start_time and r.published and r.attendance_status<>'scheduled')
    from public.correction_schedule_exceptions x join public.correction_assignments a on a.id=x.assignment_id and a.active
    join public.students s on s.id=a.student_id and s.status in ('active','재원') where x.kind in ('move','extra') and x.target_date between p_from and p_to
  ),
  roster_additions as (
    select distinct o.student_id,'regular:'||o.class_id||':'||o.lesson_date||':'||coalesce((l.starts_at at time zone 'Asia/Seoul')::time,cs.start_time,'00:00'::time) expected_key,
      '정규수업',c.name,o.lesson_date,coalesce((l.starts_at at time zone 'Asia/Seoul')::time,cs.start_time),
      exists(select 1 from public.lessons ll join public.internal_participating_attendance a on a.lesson_id=ll.id and a.student_id=o.student_id where ll.class_id=o.class_id and ll.lesson_date=o.lesson_date and ll.status='completed' and a.status::text in ('present','late','absent','excused'))
    from public.class_lesson_roster_overrides o join public.classes c on c.id=o.class_id
    join public.students s on s.id=o.student_id and s.status in ('active','재원')
    left join public.lessons l on l.class_id=o.class_id and l.lesson_date=o.lesson_date
    left join public.class_schedules cs on cs.class_id=o.class_id and cs.weekday=extract(isodow from o.lesson_date)
    where o.lesson_date between p_from and p_to
      and not exists(select 1 from public.schedule_exceptions x where x.class_id=o.class_id and x.original_date=o.lesson_date and x.kind in ('cancelled','changed','makeup'))
  ),
  scheduled_expected_raw as (
    select * from regular_fixed union select * from regular_replacements union select * from class_makeups
    union select * from roster_additions
    union all select * from special_lessons union all select * from correction_fixed union select * from correction_changes
  ),
 scheduled_expected as (select * from scheduled_expected_raw e where case when split_part(e.expected_key,':',1) in ('regular','class-makeup') then not public.internal_class_student_excluded(e.student_id,split_part(e.expected_key,':',2)::uuid,e.occurrence_date) when split_part(e.expected_key,':',1)='correction' then not public.internal_correction_closed(split_part(e.expected_key,':',2)::uuid,e.occurrence_date) else true end),
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
 when e.source='correction' then exists(select 1 from public.internal_open_correction_reports r where r.assignment_id=ca.id and r.student_id=e.student_id and r.correction_date=e.occurrence_date and r.start_time=e.start_time and r.attendance_status<>'scheduled')
 else exists(select 1 from public.internal_participating_attendance a where a.lesson_id=l.id and a.student_id=e.student_id and a.status::text in ('present','late','absent','excused')) end has_attendance
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
end $function$

;

CREATE OR REPLACE FUNCTION public.internal_alimtalk_report_sources(p_student_ids uuid[], p_from date, p_to date)
 RETURNS TABLE(student_id uuid, lessons jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
with regular_rows as (
 select a.student_id,jsonb_build_object(
      'lessonId', l.id,
      'lessonDate', to_char(l.lesson_date, 'YYYY-MM-DD'),
      'startsAt', l.starts_at,
      'classId', c.id,
      'className', c.name,
      'subject', c.subject,
      'room', coalesce(l.room, c.room),
      'teacherName', coalesce(tp.display_name, '담당 선생님'),
      'source', case when exists(select 1 from public.class_makeup_attendees ma where ma.student_id=a.student_id and ma.class_id=c.id and ma.attendance_date=l.lesson_date) then 'makeup' else 'regular' end,
      'lessonContent', coalesce(hr.lesson_content, ''),
      'homeworkContent', coalesce(hr.assigned_homework, ''),
      'examContent', coalesce(l.exam_content, ''),
      'attendance', case when a.id is null then null else jsonb_build_object(
        'status', a.status,
        'lateMinutes', a.late_minutes,
        'absenceReason', coalesce(a.absence_reason, ''),
        'note', coalesce(a.note, '')
      ) end,
      'homeworkResult', case
        when hr.id is null or (
          nullif(trim(coalesce(hr.status, '')), '') is null
          and nullif(trim(coalesce(hr.note, '')), '') is null
          and nullif(trim(coalesce(hr.inspection_status, '')), '') is null
          and nullif(trim(coalesce(hr.inspection_note, '')), '') is null
        ) then null
        else jsonb_build_object(
          'status', coalesce(nullif(hr.inspection_status, ''), hr.status, ''),
          'note', coalesce(nullif(hr.inspection_note, ''), hr.note, '')
        )
      end,
      'exams', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', er.id,
          'examType', coalesce(er.exam_type, ''),
          'examTitle', coalesce(er.exam_title, ''),
          'score', er.score,
          'maxScore', coalesce(er.max_score, 100),
          'percent', case when er.score is null or coalesce(er.max_score, 0) <= 0 then null else round(er.score / er.max_score * 100, 1) end,
          'evaluation', coalesce(er.evaluation, ''),
          'feedback', coalesce(er.feedback, '')
        ) order by er.created_at, er.id)
        from (
          -- Match staff_class_exam_results -> exams[0], the editable exam.
          -- Later duplicate inserts are historical artifacts, not additional exams.
          select current_exam.* from public.internal_participating_exams current_exam
          where current_exam.lesson_id=l.id and current_exam.student_id=a.student_id
          order by current_exam.created_at,current_exam.id limit 1
        ) er
        where (
            er.score is not null
            or nullif(trim(coalesce(er.exam_type, '')), '') is not null
            or nullif(trim(coalesce(er.exam_title, '')), '') is not null
            or nullif(trim(coalesce(er.evaluation, '')), '') is not null
            or nullif(trim(coalesce(er.feedback, '')), '') is not null
          )
      ), '[]'::jsonb)
    ) item,l.lesson_date,l.starts_at::text sort_time,
 row_number() over(partition by a.student_id order by l.lesson_date desc,l.starts_at desc) rn
 from public.lessons l join public.classes c on c.id=l.class_id
 join public.internal_participating_attendance a on a.lesson_id=l.id and a.student_id=any(p_student_ids)
 left join public.profiles tp on tp.id=l.teacher_profile_id
 left join public.internal_participating_homework hr on hr.lesson_id=l.id and hr.student_id=a.student_id
 where l.status='completed' and l.lesson_date between p_from and p_to and l.lesson_date<=current_date
), special_rows as (
 select a.student_id,jsonb_build_object(
      'lessonId',l.id,'lessonDate',to_char(l.lesson_date,'YYYY-MM-DD'),'startsAt',to_char(l.lesson_date,'YYYY-MM-DD')||'T'||l.starts_at::text||'+09:00',
      'classId',l.id,'className',case when public.internal_special_student_kind(l.id,a.student_id)='makeup' then '개별 보강' else '추가수업' end,
      'subject',coalesce(s.name,'과목 미지정'),'source',case when public.internal_special_student_kind(l.id,a.student_id)='additional' then 'extra' else public.internal_special_student_kind(l.id,a.student_id) end,'room',l.room,'teacherName',coalesce(p.display_name,'담당 선생님'),
      'lessonContent',coalesce(a.lesson_content,''),'homeworkContent',coalesce(a.assigned_homework,''),'examContent','',
      'attendance',case when a.attendance_status is null then null else jsonb_build_object('status',a.attendance_status,'lateMinutes',a.late_minutes,'absenceReason',coalesce(a.absence_reason,''),'note','') end,
      'homeworkResult',case when a.inspection_status is null then null else jsonb_build_object('status',a.inspection_status,'note',coalesce(a.inspection_note,'')) end,
      'exams',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'examType',coalesce(e.exam_type,''),'examTitle',coalesce(e.exam_title,''),'score',e.score,'maxScore',e.max_score,'percent',case when e.score is null then null else round(e.score*100.0/e.max_score,1) end,'evaluation',coalesce(e.evaluation,''),'feedback','')) from public.teacher_special_lesson_exam_results e where e.session_id=l.id and e.student_id=a.student_id),'[]'::jsonb)
    ) item,l.lesson_date,l.starts_at::text sort_time
 from public.teacher_special_lessons l join public.teacher_special_lesson_students a on a.session_id=l.id and a.student_id=any(p_student_ids)
 join public.profiles p on p.id=l.teacher_profile_id left join public.academy_subjects s on s.id=l.subject_id
 where l.status='completed' and a.attendance_status is not null and l.lesson_date between p_from and p_to
), ranked as (
 select combined.*,row_number() over(partition by combined.student_id order by lesson_date desc,sort_time desc) rn
 from (select student_id,item,lesson_date,sort_time from regular_rows where rn<=500 union all select * from special_rows) combined
), all_rows as (
 select student_id,item,lesson_date,item->>'startsAt' starts_at from ranked where rn<=500
 union all
 select r.student_id,jsonb_build_object(
      'lessonId',r.id,'lessonDate',to_char(r.correction_date,'YYYY-MM-DD'),
      'startsAt',to_char(r.correction_date,'YYYY-MM-DD')||'T'||r.start_time::text||'+09:00',
      'classId',r.assignment_id,'className','첨삭','subject',r.subject,'source','correction','room',null,
      'teacherName',coalesce(r.recorded_by_name,'담당 선생님'),'lessonContent',coalesce(r.correction_content,''),
      'homeworkContent',coalesce(r.next_preparation,r.homework_instruction,''),'examContent',coalesce(r.exam_range,''),
      'correctionTaskStatus',r.correction_task_status,'correctionTaskFeedback',coalesce(r.correction_task_feedback,''),
      'attendance',jsonb_build_object('status',r.attendance_status,'lateMinutes',r.late_minutes,'absenceReason','','note',coalesce(r.assistant_feedback,'')),
      'homeworkResult',case when r.homework_status is null then null else jsonb_build_object('status',r.homework_status,'note',coalesce(r.homework_note,'')) end,
      'exams',case when r.exam_title is null and r.exam_score is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object(
        'id',r.id,
        'examType',case when coalesce(r.exam_range,'') like '[종류]%' then coalesce(nullif(trim(replace(split_part(r.exam_range,E'\n',1),'[종류]','')),''),'첨삭 평가') else '첨삭 평가' end,
        'examTitle',coalesce(r.exam_title,''),'score',r.exam_score,'maxScore',coalesce(r.exam_max_score,100),
        'percent',case when r.exam_score is null or coalesce(r.exam_max_score,0)<=0 then null else round(r.exam_score/r.exam_max_score*100,1) end,
        'evaluation',coalesce(r.evaluation,''),'feedback',coalesce(r.teacher_instruction,''))) end
    ) item,r.correction_date,r.start_time::text
 from public.internal_open_correction_reports r join public.correction_assignments ca on ca.id=r.assignment_id
 where r.student_id=any(p_student_ids) and r.correction_date between p_from and p_to and r.published
)
select all_rows.student_id,jsonb_agg(item order by lesson_date,starts_at) from all_rows group by all_rows.student_id;
$function$

;

CREATE OR REPLACE FUNCTION public.mark_family_correction_report_read(p_student_id uuid, p_report_id uuid)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare role_now public.user_role; allowed_id uuid; ts timestamptz:=now();
begin
 role_now:=public.current_user_role();
 if role_now='student' then select id into allowed_id from public.students where profile_id=auth.uid() and id=p_student_id;
 elsif role_now='guardian' then select s.id into allowed_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() and s.id=p_student_id; end if;
 if allowed_id is null or not exists(select 1 from public.internal_open_correction_reports where id=p_report_id and student_id=allowed_id and published) then raise exception '확인할 수 없는 첨삭 리포트입니다.'; end if;
 insert into public.correction_report_reads(report_id,student_id,viewer_profile_id,viewed_at) values(p_report_id,allowed_id,auth.uid(),ts) on conflict(report_id,viewer_profile_id) do update set viewed_at=excluded.viewed_at;
 return ts;
end $function$

;

CREATE OR REPLACE FUNCTION public.staff_student_detail_insights(p_student_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_staff() then raise exception '교직원만 학생 통합 기록을 확인할 수 있습니다.'; end if;
  if not exists (select 1 from public.students where id = p_student_id) then raise exception '학생을 찾을 수 없습니다.'; end if;
  return jsonb_build_object(
    'regularAttendance', jsonb_build_object(
      'attendanceTotal', (select count(*) from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=p_student_id and l.lesson_date>=current_date-30),
      'present', (select count(*) from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=p_student_id and l.lesson_date>=current_date-30 and a.status='present'),
      'late', (select count(*) from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=p_student_id and l.lesson_date>=current_date-30 and a.status='late'),
      'absent', (select count(*) from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id where a.student_id=p_student_id and l.lesson_date>=current_date-30 and a.status in ('absent','excused'))
    ),
    'correctionAttendance', jsonb_build_object(
      'attendanceTotal', (select count(*) from public.internal_open_correction_reports r where r.student_id=p_student_id and r.correction_date>=current_date-30 and r.attendance_status<>'scheduled'),
      'present', (select count(*) from public.internal_open_correction_reports r where r.student_id=p_student_id and r.correction_date>=current_date-30 and r.attendance_status='present'),
      'late', (select count(*) from public.internal_open_correction_reports r where r.student_id=p_student_id and r.correction_date>=current_date-30 and r.attendance_status='late'),
      'absent', (select count(*) from public.internal_open_correction_reports r where r.student_id=p_student_id and r.correction_date>=current_date-30 and r.attendance_status='absent')
    ),
    'correctionAttendanceRecords', coalesce((
      select jsonb_agg(to_jsonb(q) order by q."lessonDate" desc,q."startTime" desc)
      from (
        select r.id,r.correction_date as "lessonDate",(r.subject||' 첨삭')::text as "className",r.subject,
          r.start_time as "startTime",r.attendance_status as status,
          case when r.attendance_status='late' and r.late_minutes is not null then r.late_minutes||'분 지각'
               when r.attendance_status='absent' then coalesce(nullif(r.absence_reason,''),'결석 사유 없음')
               else null end as note
        from public.internal_open_correction_reports r
        where r.student_id=p_student_id and r.attendance_status<>'scheduled'
        order by r.correction_date desc,r.start_time desc limit 30
      ) q
    ),'[]'::jsonb),
    'correctionExams', coalesce((
      select jsonb_agg(to_jsonb(q) order by q."lessonDate",q.id)
      from (
        select r.id,r.correction_date as "lessonDate",(r.subject||' 첨삭')::text as "className",r.subject,
          case when coalesce(r.exam_range,'') like '[종류]%'
            then nullif(trim(replace(split_part(r.exam_range,E'\n',1),'[종류]','')),'')
            else '첨삭 시험' end as "examType",
          coalesce(r.exam_title,'') as "examTitle",r.exam_score as score,
          coalesce(nullif(r.exam_max_score,0),100) as "maxScore",
          round(r.exam_score*100.0/coalesce(nullif(r.exam_max_score,0),100),1) as percent,
          coalesce(r.evaluation,'') as evaluation
        from public.internal_open_correction_reports r
        where r.student_id=p_student_id and r.exam_score is not null
        order by r.correction_date desc,r.created_at desc limit 50
      ) q
    ),'[]'::jsonb),
    'correctionLearning', coalesce((
      select jsonb_agg(to_jsonb(q) order by q."lessonDate" desc,q.id desc)
      from (
        select r.id,r.correction_date as "lessonDate",r.subject,
          coalesce(r.homework_instruction,'') as "homeworkInstruction",
          coalesce(r.homework_status,'') as "homeworkStatus",
          coalesce(r.homework_note,'') as "homeworkNote",
          coalesce(r.correction_content,'') as "correctionContent",
          coalesce(r.assistant_feedback,'') as "assistantFeedback"
        from public.internal_open_correction_reports r
        where r.student_id=p_student_id and (
          nullif(trim(r.homework_instruction),'') is not null or nullif(trim(r.homework_note),'') is not null or
          nullif(trim(r.correction_content),'') is not null or nullif(trim(r.assistant_feedback),'') is not null
        )
        order by r.correction_date desc,r.created_at desc limit 20
      ) q
    ),'[]'::jsonb)
  );
end
$function$

;

CREATE OR REPLACE FUNCTION public.absence_makeup_board()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_role public.user_role;
begin
  if not public.is_staff() or public.current_user_role()='assistant' then raise exception '결석·보강 조회 권한이 없습니다.'; end if;
  v_role:=public.current_user_role();
  return public.internal_special_makeup_board_overlay(jsonb_build_object(
    'isStaff',true,'role',v_role,
    'teachers',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name) from public.profiles p where p.is_active and p.role in ('admin','teacher','sub_admin','manager') and (v_role='admin' or p.id=auth.uid())),'[]'::jsonb),
    'items',coalesce((select jsonb_agg(row_data order by sort_date desc,student_name) from (
      select jsonb_build_object('attendanceId',a.id,'sourceId',a.id,'recordKind','absence','studentId',st.id,'studentName',st.name,'classId',c.id,'className',c.name,'subjectId',c.subject_id,'subjectName',coalesce(sub.name,c.subject,'과목 미지정'),'missedDate',l.lesson_date,'attendanceNote',coalesce(a.absence_reason,a.note),'sessionId',ms.id,'teacherId',ms.teacher_profile_id,'teacherName',tp.display_name,'scheduledAt',ms.scheduled_at,'endsAt',ms.ends_at,'room',ms.room,'status',ms.status,'note',ms.note,'source',case when exists(select 1 from public.class_makeup_attendees cm where cm.class_id=c.id and cm.student_id=st.id and cm.attendance_date=l.lesson_date) then 'class' else 'regular' end) row_data,
        coalesce(ms.scheduled_at,l.starts_at) sort_date,st.name student_name
      from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id join public.classes c on c.id=l.class_id join public.students st on st.id=a.student_id left join public.academy_subjects sub on sub.id=c.subject_id left join public.makeup_sessions ms on ms.attendance_id=a.id left join public.profiles tp on tp.id=ms.teacher_profile_id
      where (a.status='absent' or ms.id is not null) and (v_role='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid()))
      union all
      select jsonb_build_object('attendanceId',null,'sourceId',r.id,'recordKind','absence','studentId',st.id,'studentName',st.name,'classId',scope.class_id,'className',coalesce(scope.class_name,'첨삭수업'),'subjectId',scope.subject_id,'subjectName',coalesce(r.subject,'과목 미지정'),'missedDate',r.correction_date,'attendanceNote',r.absence_reason,'sessionId',sm.id,'teacherId',sm.teacher_profile_id,'teacherName',tp.display_name,'scheduledAt',sm.scheduled_at,'endsAt',sm.ends_at,'room',sm.room,'status',sm.status,'note',sm.note,'source','correction') row_data,
        coalesce(sm.scheduled_at,((r.correction_date+r.start_time) at time zone 'Asia/Seoul')) sort_date,st.name student_name
      from public.internal_open_correction_reports r join public.students st on st.id=r.student_id left join public.source_makeup_sessions sm on sm.source_type='correction' and sm.source_id=r.id and sm.student_id=r.student_id left join public.profiles tp on tp.id=sm.teacher_profile_id
      left join lateral (select c.id class_id,c.name class_name,c.subject_id from public.enrollments e join public.classes c on c.id=e.class_id where e.student_id=st.id and e.status='active' and c.active and (c.subject=r.subject or exists(select 1 from public.academy_subjects su where su.id=c.subject_id and su.name=r.subject)) order by c.name limit 1) scope on true
      where r.attendance_status='absent' and (v_role='admin' or exists(select 1 from public.correction_assignments ca where ca.id=r.assignment_id and (ca.tutor_profile_id=auth.uid() or ca.supervisor_profile_id=auth.uid())) or exists(select 1 from public.class_teachers ct where ct.class_id=scope.class_id and ct.profile_id=auth.uid()))
      union all
      select jsonb_build_object('attendanceId',null,'sourceId',sl.id,'recordKind','absence','studentId',st.id,'studentName',st.name,'classId',scope.class_id,'className',coalesce(scope.class_name,case when public.internal_special_student_kind(sl.id,ss.student_id)='makeup' then '개별 보강' else '추가수업' end),'subjectId',sl.subject_id,'subjectName',coalesce(sub.name,'과목 미지정'),'missedDate',sl.lesson_date,'attendanceNote',ss.absence_reason,'sessionId',sm.id,'teacherId',sm.teacher_profile_id,'teacherName',coalesce(tp.display_name,owner.display_name),'scheduledAt',sm.scheduled_at,'endsAt',sm.ends_at,'room',coalesce(sm.room,sl.room),'status',sm.status,'note',sm.note,'source',case when public.internal_special_student_kind(sl.id,ss.student_id)='makeup' then 'individual' else 'additional' end) row_data,
        coalesce(sm.scheduled_at,((sl.lesson_date+sl.starts_at) at time zone 'Asia/Seoul')) sort_date,st.name student_name
      from public.teacher_special_lessons sl join public.teacher_special_lesson_students ss on ss.session_id=sl.id join public.students st on st.id=ss.student_id left join public.academy_subjects sub on sub.id=sl.subject_id left join public.source_makeup_sessions sm on sm.source_type='special' and sm.source_id=sl.id and sm.student_id=st.id left join public.profiles tp on tp.id=sm.teacher_profile_id left join public.profiles owner on owner.id=sl.teacher_profile_id
      left join lateral (select c.id class_id,c.name class_name from public.enrollments e join public.classes c on c.id=e.class_id where e.student_id=st.id and e.status='active' and c.active and (sl.subject_id is null or c.subject_id=sl.subject_id) order by c.name limit 1) scope on true
      where ss.attendance_status='absent' and (v_role='admin' or sl.teacher_profile_id=auth.uid() or exists(select 1 from public.class_teachers ct where ct.class_id=scope.class_id and ct.profile_id=auth.uid()))
      union all
      select jsonb_build_object('attendanceId',null,'sourceId',null,'recordKind','schedule','studentId',st.id,'studentName',st.name,'classId',c.id,'className',c.name,'subjectId',c.subject_id,'subjectName',coalesce(sub.name,c.subject,'과목 미지정'),'missedDate',null,'attendanceNote',null,'sessionId',concat('class:',m.class_id,':',m.attendance_date),'teacherId',coalesce(l.teacher_profile_id,m.created_by),'teacherName',coalesce(lp.display_name,cp.display_name),'scheduledAt',coalesce(l.starts_at,((m.attendance_date+coalesce(sched.start_time,'18:00'::time)) at time zone 'Asia/Seoul')),'endsAt',coalesce(l.ends_at,((m.attendance_date+coalesce(sched.end_time,'20:00'::time)) at time zone 'Asia/Seoul')),'room',coalesce(l.room,c.room),'status',case when l.id is not null and (exists(select 1 from public.internal_participating_attendance ca where ca.lesson_id=l.id and ca.student_id=st.id) or nullif(trim(l.lesson_content),'') is not null or nullif(trim(l.homework_content),'') is not null or nullif(trim(l.exam_content),'') is not null) then 'completed' else 'scheduled' end,'note',null,'source','class') row_data,
        coalesce(l.starts_at,((m.attendance_date+coalesce(sched.start_time,'18:00'::time)) at time zone 'Asia/Seoul')) sort_date,st.name student_name
      from public.class_makeup_attendees m join public.classes c on c.id=m.class_id join public.students st on st.id=m.student_id left join public.academy_subjects sub on sub.id=c.subject_id left join lateral (select lesson.* from public.lessons lesson where lesson.class_id=m.class_id and lesson.lesson_date=m.attendance_date order by lesson.starts_at limit 1) l on true left join lateral (select cs.start_time,cs.end_time from public.class_schedules cs where cs.class_id=m.class_id order by cs.start_time limit 1) sched on true left join public.profiles lp on lp.id=l.teacher_profile_id left join public.profiles cp on cp.id=m.created_by
      where not exists(select 1 from public.internal_participating_attendance ca where ca.lesson_id=l.id and ca.student_id=st.id and ca.status='absent') and (v_role='admin' or exists(select 1 from public.class_teachers ct where ct.class_id=c.id and ct.profile_id=auth.uid()))
      union all
      select jsonb_build_object('attendanceId',null,'sourceId',sl.id,'recordKind','schedule','studentId',st.id,'studentName',st.name,'classId',scope.class_id,'className',coalesce(scope.class_name,'개별 보강'),'subjectId',sl.subject_id,'subjectName',coalesce(sub.name,'과목 미지정'),'missedDate',null,'attendanceNote',null,'sessionId',sl.id,'teacherId',sl.teacher_profile_id,'teacherName',tp.display_name,'scheduledAt',((sl.lesson_date+sl.starts_at) at time zone 'Asia/Seoul'),'endsAt',((sl.lesson_date+sl.ends_at) at time zone 'Asia/Seoul'),'room',sl.room,'status',case when sl.status='completed' then 'completed' else 'scheduled' end,'note',sl.note,'source','individual') row_data,
        ((sl.lesson_date+sl.starts_at) at time zone 'Asia/Seoul') sort_date,st.name student_name
      from public.teacher_special_lessons sl join public.teacher_special_lesson_students ss on ss.session_id=sl.id join public.students st on st.id=ss.student_id join public.profiles tp on tp.id=sl.teacher_profile_id left join public.academy_subjects sub on sub.id=sl.subject_id left join lateral (select c.id class_id,c.name class_name from public.enrollments e join public.classes c on c.id=e.class_id where e.student_id=st.id and e.status='active' and c.active and (sl.subject_id is null or c.subject_id=sl.subject_id) order by c.name limit 1) scope on true
      where public.internal_special_student_kind(sl.id,ss.student_id)='makeup' and ss.attendance_status is distinct from 'absent' and (v_role='admin' or sl.teacher_profile_id=auth.uid() or exists(select 1 from public.class_teachers ct where ct.class_id=scope.class_id and ct.profile_id=auth.uid()))
    ) rows),'[]'::jsonb)
  ));
end $function$

;

CREATE OR REPLACE FUNCTION public.staff_alimtalk_ready_students(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
  if not public.can_send_alimtalk() then raise exception '관리자만 알림톡 발송 대상을 확인할 수 있습니다.'; end if;
  if p_from is null or p_to is null or p_to<p_from or p_to-p_from>6 then raise exception '발송 기간을 확인해 주세요.'; end if;

  with days as (
    select generate_series(p_from,p_to,'1 day'::interval)::date occurrence_date
  ),
  regular_fixed as (
    select distinct e.student_id,'regular:'||cs.class_id||':'||d.occurrence_date||':'||cs.start_time expected_key,
      '정규수업' kind,c.name title,d.occurrence_date,cs.start_time,
      exists(select 1 from public.lessons l join public.internal_participating_attendance at on at.lesson_id=l.id and at.student_id=e.student_id where l.class_id=cs.class_id and l.lesson_date=d.occurrence_date and l.status='completed') completed
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
      exists(select 1 from public.lessons l join public.internal_participating_attendance at on at.lesson_id=l.id and at.student_id=e.student_id where l.class_id=x.class_id and l.lesson_date=x.replacement_date and l.status='completed')
    from public.schedule_exceptions x join public.class_schedules cs on cs.class_id=x.class_id and cs.weekday=extract(isodow from x.original_date)::smallint
    join public.classes c on c.id=x.class_id and c.active join public.enrollments e on e.class_id=c.id and e.status='active'
      and e.started_on<=x.replacement_date and (e.ended_on is null or e.ended_on>=x.replacement_date)
    join public.students s on s.id=e.student_id and s.status in ('active','재원')
    where x.kind in ('changed','makeup') and x.replacement_date between p_from and p_to
  ),
  class_makeups as (
    select distinct m.student_id,'class-makeup:'||m.class_id||':'||m.attendance_date expected_key,'보강수업',c.name,m.attendance_date,cs.start_time,
      exists(select 1 from public.lessons l join public.internal_participating_attendance at on at.lesson_id=l.id and at.student_id=m.student_id where l.class_id=m.class_id and l.lesson_date=m.attendance_date and l.status='completed')
    from public.class_makeup_attendees m join public.classes c on c.id=m.class_id
    left join public.class_schedules cs on cs.class_id=m.class_id and cs.weekday=extract(isodow from m.attendance_date)::smallint
    join public.students s on s.id=m.student_id and s.status in ('active','재원') where m.attendance_date between p_from and p_to
  ),
  special_lessons as (
    select a.student_id,'special:'||l.id expected_key,case when public.internal_special_student_kind(l.id,a.student_id)='makeup' then '개별 보강' else '추가수업' end,
      coalesce(sub.name,case when public.internal_special_student_kind(l.id,a.student_id)='makeup' then '보강' else '추가수업' end),l.lesson_date,l.starts_at,
      l.status='completed' and a.attendance_status is not null
    from public.teacher_special_lessons l join public.teacher_special_lesson_students a on a.session_id=l.id
    join public.students s on s.id=a.student_id and s.status in ('active','재원') left join public.academy_subjects sub on sub.id=l.subject_id
    where l.lesson_date between p_from and p_to
  ),
  correction_fixed as (
    select a.student_id,'correction:'||a.id||':'||d.occurrence_date||':'||a.start_time expected_key,'첨삭수업',a.subject||' 첨삭',d.occurrence_date,a.start_time,
      exists(select 1 from public.internal_open_correction_reports r where r.assignment_id=a.id and r.student_id=a.student_id and r.correction_date=d.occurrence_date and r.start_time=a.start_time and r.published and r.attendance_status<>'scheduled')
    from days d join public.correction_assignments a on a.active and a.weekday=extract(isodow from d.occurrence_date)::smallint
      and (a.valid_from is null or a.valid_from<=d.occurrence_date) and (a.valid_until is null or a.valid_until>=d.occurrence_date)
    join public.students s on s.id=a.student_id and s.status in ('active','재원')
    where not exists(select 1 from public.correction_schedule_exceptions x where x.assignment_id=a.id and x.original_date=d.occurrence_date and x.kind in ('move','cancel'))
  ),
  correction_changes as (
    select a.student_id,'correction:'||a.id||':'||x.target_date||':'||x.target_start_time expected_key,'첨삭수업',a.subject||case when x.kind='extra' then ' 추가 첨삭' else ' 첨삭' end,x.target_date,x.target_start_time,
      exists(select 1 from public.internal_open_correction_reports r where r.assignment_id=a.id and r.student_id=a.student_id and r.correction_date=x.target_date and r.start_time=x.target_start_time and r.published and r.attendance_status<>'scheduled')
    from public.correction_schedule_exceptions x join public.correction_assignments a on a.id=x.assignment_id and a.active
    join public.students s on s.id=a.student_id and s.status in ('active','재원') where x.kind in ('move','extra') and x.target_date between p_from and p_to
  ),
  scheduled_expected_raw as (
    select * from regular_fixed union select * from regular_replacements union select * from class_makeups
    union all select * from special_lessons union all select * from correction_fixed union select * from correction_changes
  ),
 scheduled_expected as (select * from scheduled_expected_raw e where case when split_part(e.expected_key,':',1) in ('regular','class-makeup') then not public.internal_class_student_excluded(e.student_id,split_part(e.expected_key,':',2)::uuid,e.occurrence_date) when split_part(e.expected_key,':',1)='correction' then not public.internal_correction_closed(split_part(e.expected_key,':',2)::uuid,e.occurrence_date) else true end),
  expected as (
    select * from scheduled_expected
    union all
    select a.student_id,'recorded-regular:'||l.id::text,'정규수업',c.name,l.lesson_date,
      (l.starts_at at time zone 'Asia/Seoul')::time,true
    from public.internal_participating_attendance a join public.lessons l on l.id=a.lesson_id
    join public.classes c on c.id=l.class_id
    join public.students s on s.id=a.student_id and s.status in ('active','재원')
    where l.status='completed' and l.lesson_date between p_from and p_to
      and not exists(select 1 from scheduled_expected e
        where e.student_id=a.student_id and e.occurrence_date=l.lesson_date
        and (e.expected_key like 'regular:'||l.class_id::text||':'||l.lesson_date::text||':%'
          or e.expected_key='class-makeup:'||l.class_id::text||':'||l.lesson_date::text))
  ),
  completed_expected as (
    select * from expected where completed
  ),
  unresolved_expected as (
    select
      e.student_id,
      min(e.expected_key) expected_key,
      case when count(*)>1 then '교차수업' else min(e.kind) end kind,
      case when count(*)>1 then string_agg(distinct e.title,' / ' order by e.title) else min(e.title) end title,
      e.occurrence_date,
      e.start_time,
      false completed
    from expected e
    where not e.completed
      and not exists (
        select 1 from expected done
        where done.student_id=e.student_id
          and done.occurrence_date=e.occurrence_date
          and done.start_time is not distinct from e.start_time
          and done.completed
      )
    group by e.student_id,e.occurrence_date,e.start_time
  ),
  resolved_expected as (
    select * from completed_expected
    union all
    select * from unresolved_expected
  ),
  readiness as materialized (
    select student_id,count(*)::integer expected_count,count(*) filter(where completed)::integer completed_count,
      coalesce(jsonb_agg(jsonb_build_object('kind',kind,'title',title,'date',occurrence_date,'time',to_char(start_time,'HH24:MI')) order by occurrence_date,start_time,title) filter(where not completed),'[]'::jsonb) missing_items
    from resolved_expected group by student_id
  ),
  report_sources as materialized (
    select * from public.internal_alimtalk_report_sources(array(select student_id from readiness),p_from,p_to)
  ),
  recipients as materialized (
    select distinct on(sg.student_id) sg.student_id,
      jsonb_build_object('guardianName',g.name,'maskedPhone',left(regexp_replace(g.phone,'[^0-9]','','g'),3)||'-****-'||right(regexp_replace(g.phone,'[^0-9]','','g'),4),'available',true) recipient
    from public.student_guardians sg join public.guardians g on g.id=sg.guardian_id
    where sg.student_id in (select student_id from readiness) and length(regexp_replace(coalesce(g.phone,''),'[^0-9]','','g')) between 10 and 11
    order by sg.student_id,sg.is_primary desc,g.created_at
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'studentId',s.id,'studentName',s.name,'school',coalesce(s.school,''),'grade',coalesce(s.grade,''),
    'expectedCount',r.expected_count,'completedCount',r.completed_count,'complete',r.completed_count=r.expected_count,'missingItems',r.missing_items,
    'sourceVersion',md5(coalesce(src.lessons,'[]'::jsonb)::text),'lessons',coalesce(src.lessons,'[]'::jsonb),'recipient',coalesce(rec.recipient,jsonb_build_object('guardianName','','maskedPhone','','available',false))
  ) order by (r.completed_count=r.expected_count) desc,s.name,s.id),'[]'::jsonb) into result
  from readiness r join public.students s on s.id=r.student_id left join report_sources src on src.student_id=s.id left join recipients rec on rec.student_id=s.id where r.expected_count>0;
  return result;
end $function$

;

CREATE OR REPLACE FUNCTION public.family_today_lessons(p_student_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare sid uuid; today date := (now() at time zone 'Asia/Seoul')::date; result jsonb;
begin
  sid:=public.internal_family_student_id(p_student_id);
  if sid is null then return '[]'::jsonb; end if;
  with rows as (
    select 'regular:'||l.id::text id,'regular' kind,'정규수업' label,coalesce(c.subject,c.name) subject,to_char(l.starts_at at time zone 'Asia/Seoul','HH24:MI') start_time,to_char(l.ends_at at time zone 'Asia/Seoul','HH24:MI') end_time,coalesce(p.display_name,'') teacher_name,coalesce(l.room,c.room,'') room,a.status::text attendance_status
    from public.lessons l join public.classes c on c.id=l.class_id left join public.profiles p on p.id=l.teacher_profile_id left join public.internal_participating_attendance a on a.lesson_id=l.id and a.student_id=sid where not public.internal_class_student_excluded(sid,c.id,today) and l.lesson_date=today and l.id=public.internal_student_class_lesson_id(sid,l.class_id,today) and (a.id is not null or (l.status<>'cancelled' and (
      exists(select 1 from public.schedule_exceptions x where x.class_id=c.id
        and x.kind in ('changed','makeup') and x.replacement_date=today
        and (x.start_time is null or x.start_time=(l.starts_at at time zone 'Asia/Seoul')::time)
        and public.student_attends_class_on(sid,c.id,x.original_date))
      or (
        public.student_attends_class_on(sid,c.id,today)
        and not exists(select 1 from public.schedule_exceptions x
          where x.class_id=c.id and x.original_date=today and x.kind in ('cancelled','changed','makeup'))
      )
    )))
    union all
    select 'special:'||l.id::text,'special',case public.internal_special_student_kind(l.id,sid) when 'makeup' then '보강' when 'extra' then '추가수업' when 'additional' then '추가수업' else '개별수업' end,coalesce(s.name,'과목 미지정'),to_char(l.starts_at,'HH24:MI'),to_char(l.ends_at,'HH24:MI'),coalesce(p.display_name,''),coalesce(l.room,''),ss.attendance_status
    from public.teacher_special_lessons l join public.teacher_special_lesson_students ss on ss.session_id=l.id and ss.student_id=sid left join public.academy_subjects s on s.id=l.subject_id left join public.profiles p on p.id=l.teacher_profile_id where l.lesson_date=today and coalesce(l.status,'scheduled')<>'cancelled'
    union all
    select 'correction:'||ca.id::text,'correction','첨삭',coalesce(ca.subject,'과목 미지정'),to_char(ca.start_time,'HH24:MI'),to_char(ca.end_time,'HH24:MI'),coalesce(p.display_name,''),'',cr.attendance_status
    from public.correction_assignments ca left join public.profiles p on p.id=coalesce(ca.tutor_profile_id,ca.teacher_profile_id) left join public.internal_open_correction_reports cr on cr.assignment_id=ca.id and cr.student_id=sid and cr.correction_date=today and cr.start_time=ca.start_time
    where not public.internal_correction_closed(ca.id,today) and ca.student_id=sid and ca.active and ca.valid_from<=today and (ca.valid_until is null or ca.valid_until>=today) and ca.weekday=extract(isodow from today)::int and not exists(select 1 from public.correction_schedule_exceptions x where x.assignment_id=ca.id and x.original_date=today and x.kind in ('cancel','move'))
    union all
    select 'correction-move:'||x.id::text,'correction','첨삭',coalesce(ca.subject,'과목 미지정'),to_char(coalesce(x.target_start_time,ca.start_time),'HH24:MI'),to_char(coalesce(x.target_end_time,ca.end_time),'HH24:MI'),coalesce(p.display_name,''),'',cr.attendance_status
    from public.correction_schedule_exceptions x join public.correction_assignments ca on ca.id=x.assignment_id and ca.student_id=sid left join public.profiles p on p.id=coalesce(ca.tutor_profile_id,ca.teacher_profile_id) left join public.internal_open_correction_reports cr on cr.assignment_id=ca.id and cr.student_id=sid and cr.correction_date=today and cr.start_time=coalesce(x.target_start_time,ca.start_time) where x.target_date=today and x.kind in ('move','extra')
  )
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'kind',kind,'label',label,'subject',subject,'startTime',start_time,'endTime',end_time,'teacherName',teacher_name,'room',room,'attendanceStatus',attendance_status) order by start_time,id),'[]'::jsonb) into result from rows;
  return result;
end $function$

;

CREATE OR REPLACE FUNCTION public.staff_alimtalk_record_links(p_delivery_id uuid DEFAULT NULL::uuid, p_student_id uuid DEFAULT NULL::uuid, p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare student uuid; refs jsonb; mode text; result jsonb; d public.learning_alimtalk_deliveries%rowtype;
begin
 if auth.uid() is null or not coalesce(public.can_send_alimtalk(),false) then raise exception '알림톡 기록 조회 권한이 없습니다.'; end if;
 if p_delivery_id is not null then
  select * into d from public.learning_alimtalk_deliveries where id=p_delivery_id;
  if not found then raise exception '발송 기록을 찾을 수 없습니다.'; end if;
  student:=d.student_id; refs:=d.source_refs; mode:='saved';
  if refs is null then
   mode:='history'; refs:=public.internal_alimtalk_source_refs(public.staff_learning_report_source(student,d.period_start,d.period_end));
  end if;
 else
  if p_student_id is null or p_from is null or p_to is null or p_to<p_from or p_to-p_from>6 then raise exception '조회할 학생과 기간을 확인해 주세요.'; end if;
  student:=p_student_id; mode:='current';
  refs:=public.internal_alimtalk_source_refs(public.staff_learning_report_source(student,p_from,p_to));
 end if;
 select coalesce(jsonb_agg(r || jsonb_build_object('target',case
  when cr.id is not null and ca.id is not null then jsonb_build_object('source','correction','classId',null,'sessionId',null,'assignmentId',cr.assignment_id,'date',cr.correction_date,'time',to_char(cr.start_time,'HH24:MI'),'title',cr.subject||' 첨삭','kind','첨삭')
  when l.id is not null and c.id is not null then jsonb_build_object('source','regular','classId',l.class_id,'sessionId',null,'assignmentId',null,'date',l.lesson_date,'time',to_char(l.starts_at at time zone 'Asia/Seoul','HH24:MI'),'title',c.name,'kind',case when r->>'source'='makeup' then '클래스 보강' else '정규수업' end)
  when sl.id is not null then jsonb_build_object('source','special','classId',null,'sessionId',sl.id,'assignmentId',null,'date',sl.lesson_date,'time',to_char(sl.starts_at,'HH24:MI'),'title',r->>'subject','kind',case when r->>'source'='makeup' then '보강' else '추가수업' end)
  else null end)),'[]'::jsonb) into result
 from jsonb_array_elements(refs) r
 left join correction_reports cr on r->>'source'='correction' and cr.id=(r->>'lessonId')::uuid and cr.student_id=student
 left join correction_assignments ca on ca.id=cr.assignment_id
 left join lessons l on r->>'source'<>'correction' and l.id=(r->>'lessonId')::uuid
  and exists(select 1 from attendance a where a.lesson_id=l.id and a.student_id=student)
 left join classes c on c.id=l.class_id
 left join teacher_special_lessons sl on r->>'source' in ('makeup','extra') and sl.id=(r->>'lessonId')::uuid
  and exists(select 1 from teacher_special_lesson_students ss where ss.session_id=sl.id and ss.student_id=student);
 return jsonb_build_object('mode',mode,'items',result,'studentId',student);
end $function$

;

CREATE OR REPLACE FUNCTION public.family_learning_calendar_schedule(p_student_id uuid DEFAULT NULL::uuid, p_month date DEFAULT (date_trunc('month'::text, timezone('Asia/Seoul'::text, now())))::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  base jsonb;
  sid uuid;
  month_start date := date_trunc('month', p_month)::date;
  month_end date := (date_trunc('month', p_month) + interval '1 month - 1 day')::date;
  result jsonb;
begin
  base := public.family_live_dashboard(p_student_id);
  sid := nullif(base->'selectedStudent'->>'id', '')::uuid;
  if sid is null then return '[]'::jsonb; end if;

  with recursive month_days as (
    select month_start as class_date
    union all
    select class_date + 1 from month_days where class_date < month_end
  ), saved_source as (
    select l.*,a.status::text attendance_status,c.name,c.subject,c.room class_room
    from lessons l join classes c on c.id=l.class_id
    left join public.internal_participating_attendance a on a.lesson_id=l.id and a.student_id=sid
    where l.lesson_date between month_start and month_end and l.lesson_date<=(now() at time zone 'Asia/Seoul')::date
      and public.internal_student_has_class_record(sid,l.class_id,l.lesson_date)
      and l.id=public.internal_student_class_lesson_id(sid,l.class_id,l.lesson_date)
  ), saved_regular as (
    select 'regular-saved:'||id::text id,lesson_date class_date,
      (starts_at at time zone 'Asia/Seoul')::time start_time,(ends_at at time zone 'Asia/Seoul')::time end_time,
      'regular'::text kind,'정규수업'::text label,name title,subject,coalesce(room,class_room,'') room,
      case when status='cancelled' then 'cancelled' else 'scheduled' end state,attendance_status
    from saved_source
  ), regular_base as (
    select
      'regular:' || cs.id::text || ':' || d.class_date::text as id,
      d.class_date, cs.start_time, cs.end_time, 'regular'::text as kind,
      '정규수업'::text as label, c.name as title, c.subject,
      coalesce(c.room, '') as room, 'scheduled'::text as state, null::text as attendance_status
    from month_days d
    join public.class_schedules cs on cs.weekday = extract(isodow from d.class_date)::smallint
      and (cs.valid_from is null or cs.valid_from <= d.class_date)
      and (cs.valid_until is null or cs.valid_until >= d.class_date)
    join public.classes c on c.id = cs.class_id and c.active
    join public.enrollments e on e.class_id = c.id and e.student_id = sid
      and e.status = 'active' and e.started_on <= d.class_date
      and (e.ended_on is null or e.ended_on >= d.class_date)
    where not public.internal_class_student_excluded(sid,c.id,d.class_date) and not exists(select 1 from saved_source l where l.class_id=c.id and l.lesson_date=d.class_date)
      and (not exists(select 1 from public.student_schedule_assignments ssa where ssa.student_id = sid)
      or exists(select 1 from public.student_schedule_assignments ssa where ssa.student_id = sid and ssa.class_schedule_id = cs.id))
      and not exists (
        select 1 from public.schedule_exceptions x
        where x.class_id = c.id and x.original_date = d.class_date
          and x.kind in ('cancelled', 'changed', 'makeup')
      )
  ), regular_replacements as (
    select
      'regular-change:' || x.id::text as id, x.replacement_date as class_date,
      coalesce(x.start_time, cs.start_time) as start_time, coalesce(x.end_time, cs.end_time) as end_time,
      case when x.kind = 'makeup' then 'makeup' else 'regular' end as kind,
      case when x.kind = 'makeup' then '보강' else '변경수업' end as label,
      c.name as title, c.subject, coalesce(x.room, c.room, '') as room,
      'scheduled'::text as state, null::text as attendance_status
    from public.schedule_exceptions x
    join public.classes c on c.id = x.class_id and c.active
    join public.enrollments e on e.class_id = c.id and e.student_id = sid and e.status = 'active'
    left join lateral (
      select s.start_time, s.end_time from public.class_schedules s
      where s.class_id = c.id and s.weekday=extract(isodow from x.original_date)::smallint
        and (s.valid_from is null or s.valid_from<=x.original_date) and (s.valid_until is null or s.valid_until>=x.original_date)
        and public.student_uses_class_schedule(sid,s.id) order by s.start_time limit 1
    ) cs on true
    where not public.internal_class_student_excluded(sid,c.id,x.replacement_date) and x.replacement_date between month_start and month_end
      and x.kind in ('changed', 'makeup')
      and public.internal_student_regular_class_on(sid,c.id,x.original_date)
      and not exists(select 1 from saved_source l where l.class_id=c.id and l.lesson_date=x.replacement_date)
      and e.started_on <= x.replacement_date
      and (e.ended_on is null or e.ended_on >= x.replacement_date)
  ), correction_base as (
    select
      'correction:' || a.id::text || ':' || d.class_date::text as id,
      d.class_date, a.start_time, a.end_time, 'correction'::text as kind,
      '첨삭'::text as label, coalesce(a.subject, '첨삭') || ' 첨삭수업' as title,
      coalesce(a.subject, '첨삭') as subject, ''::text as room,
      'scheduled'::text as state, null::text as attendance_status
    from month_days d
    join public.correction_assignments a on a.student_id = sid and a.active
      and a.weekday = extract(isodow from d.class_date)::smallint
      and a.valid_from <= d.class_date and (a.valid_until is null or a.valid_until >= d.class_date)
    where not public.internal_correction_closed(a.id,d.class_date) and not exists (
      select 1 from public.correction_schedule_exceptions x
      where x.assignment_id = a.id and x.original_date = d.class_date and x.kind in ('move', 'cancel')
    )
  ), correction_changes as (
    select
      'correction-change:' || x.id::text as id, x.target_date as class_date,
      coalesce(x.target_start_time, a.start_time) as start_time,
      coalesce(x.target_end_time, a.end_time) as end_time,
      'correction'::text as kind,
      case when x.kind = 'extra' then '추가 첨삭' else '변경 첨삭' end as label,
      coalesce(a.subject, '첨삭') || ' 첨삭수업' as title,
      coalesce(a.subject, '첨삭') as subject, ''::text as room,
      'scheduled'::text as state, null::text as attendance_status
    from public.correction_schedule_exceptions x
    join public.correction_assignments a on a.id = x.assignment_id and a.student_id = sid
    where x.target_date between month_start and month_end and x.kind in ('move', 'extra')
  ), special as (
    select
      'special:' || l.id::text as id, l.lesson_date as class_date,
      l.starts_at as start_time, l.ends_at as end_time,
      case when public.internal_special_student_kind(l.id,sid) = 'makeup' then 'makeup' else 'extra' end as kind,
      case when public.internal_special_student_kind(l.id,sid) = 'makeup' then '보강' else '추가수업' end as label,
      coalesce(s.name, case when public.internal_special_student_kind(l.id,sid) = 'makeup' then '보강수업' else '추가수업' end) as title,
      coalesce(s.name, '개별수업') as subject, coalesce(l.room, '') as room,
      case when coalesce(l.status, 'scheduled') = 'cancelled' then 'cancelled' else 'scheduled' end as state,
      ss.attendance_status
    from public.teacher_special_lessons l
    join public.teacher_special_lesson_students ss on ss.session_id = l.id and ss.student_id = sid
    left join public.academy_subjects s on s.id = l.subject_id
    where l.lesson_date between month_start and month_end
  ), rows as (
    select * from saved_regular
    union all select * from regular_base
    union all select * from regular_replacements
    union all select * from correction_base
    union all select * from correction_changes
    union all select * from special
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'date', to_char(class_date, 'YYYY-MM-DD'),
    'startTime', to_char(start_time, 'HH24:MI'), 'endTime', to_char(end_time, 'HH24:MI'),
    'kind', kind, 'label', label, 'title', title, 'subject', subject,
    'room', room, 'state', state, 'attendanceStatus', attendance_status
  ) order by class_date, start_time, id), '[]'::jsonb) into result from rows;
  return result;
end;
$function$

;

CREATE OR REPLACE FUNCTION public.staff_class_day(p_class_id uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 수업 기록을 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  select jsonb_build_object('closureReason',public.internal_academy_closure(p_date,'regular'),'rosterVersion',public.internal_class_participation_version(p_class_id,p_date),'lessonId',l.id,'examContent',null,'lessonContent',null,'homeworkContent',null,
    'students',coalesce((select jsonb_agg(jsonb_build_object(
      'id',s.id,'name',s.name,'school',s.school,'grade',s.grade,'status',a.status,
      'lateMinutes',a.late_minutes,'absenceReason',a.absence_reason,'note',a.note,
      'excluded',public.internal_class_student_excluded(s.id,p_class_id,p_date),
      'exclusionReason',coalesce((select x.reason from public.class_lesson_participation x where x.class_id=p_class_id and x.lesson_date=p_date and x.student_id=s.id),''),
      'directAdded',exists(select 1 from public.class_lesson_roster_overrides o where o.class_id=p_class_id and o.lesson_date=p_date and o.student_id=s.id)
    ) order by s.name)
      from public.students s left join public.attendance a on a.student_id=s.id and a.lesson_id=l.id
      where public.student_attends_class_on(s.id,p_class_id,p_date)),'[]'::jsonb))
  into result from public.classes c left join lateral(select lesson.* from public.lessons lesson where lesson.class_id=c.id and lesson.lesson_date=p_date and lesson.id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by lesson.starts_at limit 1) l on true where c.id=p_class_id;
  return coalesce(result,jsonb_build_object('lessonId',null,'examContent',null,'lessonContent',null,'homeworkContent',null,'students','[]'::jsonb));
end $function$

;

CREATE OR REPLACE FUNCTION public.staff_set_class_lesson_participants(p_class_id uuid, p_date date, p_changes jsonb, p_expected_version text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare r jsonb; sid uuid; ids uuid[]:='{}'; is_excluded boolean; why text; snap jsonb; draft_row jsonb; live_row jsonb;
begin
 if auth.uid() is null or not coalesce(public.is_staff(),false) or
 (public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid())) then
  raise exception '담당 클래스의 수업 대상만 변경할 수 있습니다.';
 end if;
 if p_date is null or jsonb_typeof(p_changes) is distinct from 'array' or jsonb_array_length(p_changes)>300 then raise exception '변경할 수업 대상을 확인해 주세요.'; end if;
 perform pg_advisory_xact_lock_shared(hashtextextended('academy-closure',0));
 perform pg_advisory_xact_lock(hashtextextended(p_class_id::text||':'||p_date::text,0));
 if p_expected_version is distinct from public.internal_class_participation_version(p_class_id,p_date) then
  raise exception '다른 선생님이 수업 대상을 변경했습니다. 최신 명단을 확인해 주세요.';
 end if;
 for r in select value from jsonb_array_elements(p_changes) order by value->>'studentId' loop
  sid:=(r->>'studentId')::uuid;
  if sid is null or sid=any(ids) or jsonb_typeof(r->'excluded') is distinct from 'boolean' then raise exception '변경할 학생을 확인해 주세요.'; end if;
  ids:=array_append(ids,sid);is_excluded:=(r->>'excluded')::boolean;why:=trim(coalesce(r->>'reason',''));
  perform pg_advisory_xact_lock(hashtextextended('alimtalk-source:'||sid||':'||p_date,0));
  if char_length(why)>120 then raise exception '변경 사유는 120자 이내로 입력해 주세요.'; end if;
  if not public.student_attends_class_on(sid,p_class_id,p_date) and not exists(select 1 from public.class_lesson_participation x where x.class_id=p_class_id and x.lesson_date=p_date and x.student_id=sid) then
   raise exception '이 날짜의 수업 명단에 없는 학생입니다.';
  end if;
  if is_excluded then
   snap:=public.staff_class_edit_snapshot(p_class_id,p_date);
   select value into draft_row from jsonb_array_elements(coalesce(snap->'revision'->'payload'->'rows','[]')) where value->>'studentId'=sid::text;
   select value into live_row from jsonb_array_elements(snap->'day'->'students') where value->>'id'=sid::text;
   if draft_row is not null and (
    nullif(draft_row->>'status','') is distinct from (case when live_row->>'status'='excused' then 'absent' else nullif(live_row->>'status','') end)
    or nullif(draft_row->>'lateMinutes','') is distinct from nullif(live_row->>'lateMinutes','')
    or coalesce(draft_row->>'absenceReason','') is distinct from coalesce(live_row->>'absenceReason','')
    or coalesce(draft_row->>'note','') is distinct from coalesce(live_row->>'note','')
   ) then raise exception '수정 중인 출결이 있습니다. 출결 수정 내용을 먼저 반영한 뒤 수업 대상을 변경해 주세요. 임시저장 내용은 유지됩니다.'; end if;
  end if;
  if is_excluded and exists(select 1 from public.attendance a join public.lessons l on l.id=a.lesson_id
   where a.student_id=sid and l.class_id=p_class_id and l.lesson_date=p_date and (
    exists(select 1 from public.makeup_sessions m where m.attendance_id=a.id and m.status<>'cancelled')
    or exists(select 1 from public.teacher_special_lesson_students s where s.makeup_source='regular' and s.makeup_source_id=a.id))) then
   raise exception '연결된 보강이 있는 학생입니다. 보강 일정을 먼저 확인해 주세요.';
  end if;
  if not is_excluded and public.internal_academy_closure(p_date,'regular') is not null then
   insert into public.academy_day_openings(kind,entity_id,student_id,lesson_date,updated_by) values('regular',p_class_id,sid,p_date,auth.uid()) on conflict do nothing;
  end if;
  insert into public.class_lesson_participation(class_id,lesson_date,student_id,excluded,reason,updated_by)
  values(p_class_id,p_date,sid,is_excluded,why,auth.uid()) on conflict(class_id,lesson_date,student_id)
  do update set excluded=excluded.excluded,reason=excluded.reason,updated_by=excluded.updated_by,updated_at=clock_timestamp();
 end loop;
 insert into public.staff_live_signals(key,topic,entity_id,class_id,record_date)
 values('record:'||p_class_id||':'||p_date,'record',p_class_id,p_class_id,p_date)
 on conflict(key) do update set changed_at=clock_timestamp();
 return public.staff_class_edit_snapshot(p_class_id,p_date);
end $function$

;

CREATE OR REPLACE FUNCTION public.correction_management_board_v2(p_anchor text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_anchor date:=coalesce(nullif(p_anchor,'')::date,(timezone('Asia/Seoul',now()))::date);v_start date;v_end date;
begin
  if not public.is_staff() then raise exception '교직원만 첨삭 관리를 확인할 수 있습니다.'; end if;
  v_start:=v_anchor-(extract(isodow from v_anchor)::int-1);v_end:=v_start+6;
  return jsonb_build_object('closureDays',coalesce((select jsonb_agg(jsonb_build_object('date',d::date::text,'reason',public.internal_academy_closure(d::date,'correction'))) from generate_series(v_start,v_end,interval '1 day') d where public.internal_academy_closure(d::date,'correction') is not null),'[]'::jsonb),
    'weekStart',to_char(v_start,'YYYY-MM-DD'),
    'students',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'school',s.school,'grade',s.grade) order by s.name) from public.students s where s.status in ('active','재원')),'[]'::jsonb),
    'staff',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name) from public.profiles p where p.role::text in ('admin','teacher','sub_admin')),'[]'::jsonb),
    'assignments',coalesce((select jsonb_agg(jsonb_build_object(
      'closedDates',coalesce((select jsonb_agg(d::date::text) from generate_series(v_start,v_end,interval '1 day') d where public.internal_correction_closed(a.id,d::date)),'[]'::jsonb),'id',a.id,'studentId',a.student_id,'studentName',s.name,'school',s.school,'grade',s.grade,'subject',a.subject,
      'weekday',a.weekday,'startTime',to_char(a.start_time,'HH24:MI:SS'),'endTime',to_char(a.end_time,'HH24:MI:SS'),
      'active',a.active,'validFrom',to_char(a.valid_from,'YYYY-MM-DD'),'validUntil',case when a.valid_until is null then null else to_char(a.valid_until,'YYYY-MM-DD') end,
      'isDateOverride',(not a.active and a.valid_until is not null and (timezone('Asia/Seoul',a.created_at))::date>a.valid_until),
      'tutorId',a.tutor_profile_id,'tutorName',tp.display_name,'supervisorId',a.supervisor_profile_id,'supervisorName',sp.display_name,'note',a.note
    ) order by a.weekday,a.start_time,a.subject,s.name)
      from public.correction_assignments a join public.students s on s.id=a.student_id
      left join public.profiles tp on tp.id=a.tutor_profile_id left join public.profiles sp on sp.id=a.supervisor_profile_id
      where a.subject is not null and a.start_time is not null and a.end_time is not null
        and (
          (a.valid_from<=v_end and (a.valid_until is null or a.valid_until>=v_start))
          or exists(select 1 from public.correction_schedule_exceptions x where x.assignment_id=a.id and (x.original_date between v_start and v_end or x.target_date between v_start and v_end))
        )),'[]'::jsonb),
    'exceptions',coalesce((select jsonb_agg(jsonb_build_object(
      'id',e.id,'assignmentId',e.assignment_id,'originalDate',to_char(e.original_date,'YYYY-MM-DD'),'kind',e.kind,
      'targetDate',case when e.target_date is null then null else to_char(e.target_date,'YYYY-MM-DD') end,
      'targetStartTime',case when e.target_start_time is null then null else to_char(e.target_start_time,'HH24:MI:SS') end,
      'targetEndTime',case when e.target_end_time is null then null else to_char(e.target_end_time,'HH24:MI:SS') end,'note',e.note
    ) order by e.original_date,e.created_at)
      from public.correction_schedule_exceptions e join public.correction_assignments a on a.id=e.assignment_id
      where a.subject is not null and (e.original_date between v_start and v_end or (e.target_date is not null and e.target_date between v_start and v_end))),'[]'::jsonb)
  );
end $function$

;

CREATE OR REPLACE FUNCTION public.correction_day_board(p_date text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_date date:=coalesce(nullif(p_date,'')::date,(timezone('Asia/Seoul',now()))::date);v_weekday int:=extract(isodow from v_date)::int;
begin
  if not public.is_staff() then raise exception '교직원만 첨삭 진행 명단을 확인할 수 있습니다.'; end if;
  return jsonb_build_object('closureDays',coalesce((select jsonb_agg(jsonb_build_object('date',d::date::text,'reason',public.internal_academy_closure(d::date,'correction'))) from generate_series(v_date,v_date,interval '1 day') d where public.internal_academy_closure(d::date,'correction') is not null),'[]'::jsonb),
    'assignments',coalesce((select jsonb_agg(jsonb_build_object(
      'closedDates',coalesce((select jsonb_agg(d::date::text) from generate_series(v_date,v_date,interval '1 day') d where public.internal_correction_closed(a.id,d::date)),'[]'::jsonb),'id',a.id,'studentId',a.student_id,'studentName',s.name,'school',s.school,'grade',s.grade,'subject',a.subject,
      'weekday',a.weekday,'startTime',to_char(a.start_time,'HH24:MI:SS'),'endTime',to_char(a.end_time,'HH24:MI:SS'),
      'validFrom',to_char(a.valid_from,'YYYY-MM-DD'),'validUntil',case when a.valid_until is null then null else to_char(a.valid_until,'YYYY-MM-DD') end,
      'isDateOverride',(not a.active and a.valid_until is not null and (timezone('Asia/Seoul',a.created_at))::date>a.valid_until),
      'tutorName',tp.display_name,'supervisorName',sp.display_name,'note',a.note
    ) order by a.start_time,a.subject,s.name)
      from public.correction_assignments a join public.students s on s.id=a.student_id
      left join public.profiles tp on tp.id=a.tutor_profile_id left join public.profiles sp on sp.id=a.supervisor_profile_id
      where a.subject is not null and (
        (a.weekday=v_weekday and a.valid_from<=v_date and (a.valid_until is null or a.valid_until>=v_date))
        or exists(select 1 from public.correction_schedule_exceptions x where x.assignment_id=a.id and (x.original_date=v_date or x.target_date=v_date))
      )),'[]'::jsonb),
    'exceptions',coalesce((select jsonb_agg(jsonb_build_object(
      'id',e.id,'assignmentId',e.assignment_id,'originalDate',to_char(e.original_date,'YYYY-MM-DD'),'kind',e.kind,
      'targetDate',case when e.target_date is null then null else to_char(e.target_date,'YYYY-MM-DD') end,
      'targetStartTime',case when e.target_start_time is null then null else to_char(e.target_start_time,'HH24:MI:SS') end,
      'targetEndTime',case when e.target_end_time is null then null else to_char(e.target_end_time,'HH24:MI:SS') end,'note',e.note
    ) order by e.created_at)
      from public.correction_schedule_exceptions e join public.correction_assignments a on a.id=e.assignment_id
      where a.subject is not null and (e.original_date=v_date or e.target_date=v_date)),'[]'::jsonb)
  );
end $function$

;

-- A stale preview must never send a lesson excluded since it was opened.
create or replace function public.staff_claim_learning_alimtalk_current(p_student_id uuid,p_report_type text,p_period_start date,p_period_end date,p_lesson_summary text,p_attendance_summary text,p_learning_summary text,p_source_version text)
returns table(id uuid,recipient_phone text,guardian_name text,student_name text,template_variables jsonb)
language plpgsql security definer set search_path=public as $$
declare current_lessons jsonb; d date;
begin
 if not public.can_send_alimtalk() then raise exception '관리자만 알림톡을 발송할 수 있습니다.'; end if;
 if p_period_start is null or p_period_end is null or p_period_end<p_period_start or p_period_end-p_period_start>6 then raise exception '발송 기간을 확인해 주세요.'; end if;
 perform pg_advisory_xact_lock_shared(hashtextextended('academy-closure',0));
 for d in select generate_series(p_period_start,p_period_end,interval '1 day')::date loop
  perform pg_advisory_xact_lock(hashtextextended('alimtalk-source:'||p_student_id||':'||d,0));
 end loop;
 select lessons into current_lessons from public.internal_alimtalk_report_sources(array[p_student_id],p_period_start,p_period_end);
 if coalesce(jsonb_array_length(current_lessons),0)=0 then raise exception '발송할 수업 기록이 없습니다. 대상을 새로고침해 주세요.'; end if;
 -- Older open tabs remain compatible until this student's participation has been changed.
 if p_source_version is null and not exists(select 1 from public.academy_closures where starts_on<=p_period_end and ends_on>=p_period_start) and not exists(select 1 from public.class_lesson_participation x where x.student_id=p_student_id and x.lesson_date between p_period_start and p_period_end) then
  return query select * from public.staff_claim_learning_alimtalk(p_student_id,p_report_type,p_period_start,p_period_end,p_lesson_summary,p_attendance_summary,p_learning_summary);
  return;
 end if;
 if p_source_version is distinct from md5(current_lessons::text) then raise exception '수업 기록 또는 수업 대상이 변경됐습니다. 대상을 새로고침하고 미리보기를 확인해 주세요.'; end if;
 return query select * from public.staff_claim_learning_alimtalk(p_student_id,p_report_type,p_period_start,p_period_end,p_lesson_summary,p_attendance_summary,p_learning_summary);
end $$;
revoke all on function public.staff_claim_learning_alimtalk_current(uuid,text,date,date,text,text,text,text) from public,anon;
grant execute on function public.staff_claim_learning_alimtalk_current(uuid,text,date,date,text,text,text,text) to authenticated;


CREATE OR REPLACE FUNCTION public.staff_class_agenda(p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
 ), saved_slots as (
 select 'saved:'||l.id key,c.id class_id,null::uuid session_id,c.name,c.subject,c.color,coalesce(l.room,c.room) room,
 (l.starts_at at time zone 'Asia/Seoul')::time start_time,(l.ends_at at time zone 'Asia/Seoul')::time end_time,'정규수업'::text kind
 from allowed c join lessons l on l.class_id=c.id and l.lesson_date=p_date
 where l.id=public.internal_class_record_lesson_id(c.id,p_date)
 and (l.status='completed' or exists(select 1 from public.internal_participating_attendance a where a.lesson_id=l.id)
   or exists(select 1 from public.internal_participating_exams e where e.lesson_id=l.id) or exists(select 1 from public.internal_participating_homework h where h.lesson_id=l.id))
 and not exists(select 1 from slots s where s.class_id=c.id)
 and not exists(select 1 from makeup_slots s where s.class_id=c.id)
 ), all_slots as (
 select distinct on(class_id,start_time,end_time) * from (
 select * from slots union all select * from makeup_slots union all select * from saved_slots
 ) combined order by class_id,start_time,end_time,key
 ), entries as (
 select s.*, exists(select 1 from lessons l where l.class_id=s.class_id and l.lesson_date=p_date and l.status='completed') completed,
 (select count(*) from students st where st.status in ('active','재원') and public.student_attends_class_on(st.id,s.class_id,p_date) and not public.internal_class_student_excluded(st.id,s.class_id,p_date)) student_count,
 array(select t.profile_id from class_teachers t where t.class_id=s.class_id) teacher_ids
 from all_slots s
 union all
 select 'special:'||l.id,null::uuid,l.id,coalesce(a.name,'수업')||case when l.kind='makeup' then ' 보강' else ' 추가수업' end,
 coalesce(a.main_subject,a.name,'수업'),'#8e888b',l.room,l.starts_at,l.ends_at,case when l.kind='makeup' then '개별 보강' else '추가수업' end,
 l.status='completed',(select count(*) from teacher_special_lesson_students st where st.session_id=l.id),array[l.teacher_profile_id]
 from teacher_special_lessons l left join academy_subjects a on a.id=l.subject_id
 where l.lesson_date=p_date and (public.current_user_role()='admin' or l.teacher_profile_id=auth.uid())
 )
 select coalesce(jsonb_agg(jsonb_build_object('closureReason',case when class_id is not null and student_count=0 then public.internal_academy_closure(p_date,'regular') else null end,'key',key,'classId',class_id,'sessionId',session_id,'name',name,'subject',subject,'color',color,'room',room,'startTime',to_char(start_time,'HH24:MI'),'endTime',to_char(end_time,'HH24:MI'),'kind',kind,'completed',completed,'studentCount',student_count,'teacherIds',teacher_ids) order by start_time,name),'[]'::jsonb) into result from entries;
 return result;
end $function$

;

CREATE OR REPLACE FUNCTION public.staff_dashboard_live()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with today as (
    select (now() at time zone 'Asia/Seoul')::date as day,
           extract(isodow from now() at time zone 'Asia/Seoul')::smallint as weekday
  ), attendance_totals as (
    select
      count(*) filter (where a.status = 'present') as present_count,
      count(*) filter (where a.status = 'late') as late_count,
      count(*) filter (where a.status = 'absent') as absent_count,
      count(*) as checked_count,
      count(*) filter (where a.makeup_required) as makeup_count
    from public.internal_participating_attendance a
    join public.lessons l on l.id = a.lesson_id
    join today t on t.day = l.lesson_date
  )
  select case when public.is_staff() then jsonb_build_object(
    'todayClasses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', cs.id,
        'time', cs.start_time,
        'name', c.name,
        'room', c.room,
        'color', c.color,
        'teachers', coalesce((select string_agg(p.display_name, ' · ' order by p.display_name) from public.class_teachers ct join public.profiles p on p.id = ct.profile_id where ct.class_id = c.id), '담당 미배정'),
        'enrolled', (select count(*) from public.enrollments e where e.class_id = c.id and e.status = 'active'),
        'present', (select count(*) from public.lessons l join public.internal_participating_attendance a on a.lesson_id = l.id where l.class_id = c.id and l.lesson_date = t.day and a.status = 'present')
      ) order by cs.start_time)
      from public.class_schedules cs
      join public.classes c on c.id = cs.class_id
      cross join today t
      where cs.weekday = t.weekday and c.active and (public.internal_academy_closure(t.day,'regular') is null or exists(select 1 from public.academy_day_openings o where o.kind='regular' and o.entity_id=c.id and o.lesson_date=t.day))
        and (cs.valid_from is null or cs.valid_from <= t.day)
        and (cs.valid_until is null or cs.valid_until >= t.day)
    ), '[]'::jsonb),
    'attendance', (select jsonb_build_object('present', present_count, 'late', late_count, 'absent', absent_count, 'checked', checked_count, 'makeup', makeup_count) from attendance_totals),
    'weekAttendance', coalesce((
      select jsonb_agg(jsonb_build_object('weekday', daily.weekday, 'present', daily.present, 'late', daily.late, 'absent', daily.absent, 'checked', daily.checked) order by daily.weekday)
      from (
        select extract(isodow from days.day)::smallint as weekday,
               count(a.id) filter (where a.status = 'present') as present,
               count(a.id) filter (where a.status = 'late') as late,
               count(a.id) filter (where a.status = 'absent') as absent,
               count(a.id) as checked
        from today t
        cross join lateral generate_series(date_trunc('week', t.day::timestamp), date_trunc('week', t.day::timestamp) + interval '4 days', interval '1 day') days(day)
        left join public.lessons l on l.lesson_date = days.day::date
        left join public.internal_participating_attendance a on a.lesson_id = l.id
        group by days.day
      ) daily
    ), '[]'::jsonb)
  ) else null end
$function$

;

create or replace function public.staff_patch_class_record_with_roster(p_class_id uuid,p_date date,p_changes jsonb,p_expected_state text,p_mode text,p_roster_version text)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if auth.uid() is null or not coalesce(public.is_staff(),false) or
 (public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid())) then raise exception '담당 클래스만 수정할 수 있습니다.'; end if;
 perform pg_advisory_xact_lock_shared(hashtextextended('academy-closure',0));
 perform pg_advisory_xact_lock(hashtextextended(p_class_id::text||':'||p_date::text,0));
 if p_roster_version is distinct from public.internal_class_participation_version(p_class_id,p_date) then raise exception '수업 대상이 변경됐습니다. 최신 명단을 확인한 뒤 저장해 주세요.'; end if;
 return public.staff_patch_class_record(p_class_id,p_date,p_changes,p_expected_state,p_mode);
end $$;
revoke all on function public.staff_patch_class_record_with_roster(uuid,date,jsonb,text,text,text) from public,anon;
grant execute on function public.staff_patch_class_record_with_roster(uuid,date,jsonb,text,text,text) to authenticated;
