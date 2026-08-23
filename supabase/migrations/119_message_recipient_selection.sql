-- 문자 발송 대상을 조건별로 검색하고 선택한 학생만 안전하게 대기열에 등록합니다.

create or replace function public.staff_message_target_options()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case when public.is_staff() then jsonb_build_object(
    'students', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', s.id,
        'name', s.name,
        'school', coalesce(s.school, ''),
        'grade', coalesce(s.grade, ''),
        'classIds', coalesce((select jsonb_agg(distinct e.class_id) from public.enrollments e where e.student_id=s.id and e.status='active'), '[]'::jsonb),
        'classNames', coalesce((select jsonb_agg(distinct c.name order by c.name) from public.enrollments e join public.classes c on c.id=e.class_id where e.student_id=s.id and e.status='active' and c.active), '[]'::jsonb),
        'subjects', coalesce((select jsonb_agg(distinct coalesce(sub.name,c.subject) order by coalesce(sub.name,c.subject)) from public.enrollments e join public.classes c on c.id=e.class_id left join public.academy_subjects sub on sub.id=c.subject_id where e.student_id=s.id and e.status='active' and c.active), '[]'::jsonb)
      ) order by s.name, s.school, s.grade)
      from public.students s where s.status in ('active','재원')
    ), '[]'::jsonb),
    'classes', coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'name',c.name) order by c.name) from public.classes c where c.active), '[]'::jsonb),
    'grades', coalesce((select jsonb_agg(x.grade order by x.grade) from (select distinct trim(s.grade) grade from public.students s where s.status in ('active','재원') and nullif(trim(s.grade),'') is not null) x), '[]'::jsonb),
    'schools', coalesce((select jsonb_agg(x.school order by x.school) from (select distinct trim(s.school) school from public.students s where s.status in ('active','재원') and nullif(trim(s.school),'') is not null) x), '[]'::jsonb),
    'subjects', coalesce((select jsonb_agg(x.subject order by x.subject) from (select distinct coalesce(sub.name,c.subject) subject from public.classes c left join public.academy_subjects sub on sub.id=c.subject_id where c.active and nullif(trim(coalesce(sub.name,c.subject)),'') is not null) x), '[]'::jsonb)
  ) else jsonb_build_object('students','[]'::jsonb,'classes','[]'::jsonb,'grades','[]'::jsonb,'schools','[]'::jsonb,'subjects','[]'::jsonb) end
$$;

create or replace function public.staff_message_recipient_preview_selected(p_student_ids uuid[], p_recipient_kind text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with target_students as (
    select distinct s.id, s.name, s.phone from public.students s
    where s.status in ('active','재원') and s.id=any(coalesce(p_student_ids,'{}'::uuid[]))
  ), recipients as (
    select ts.id student_id,ts.name student_name,ts.name recipient_name,ts.phone,'student'::text kind
    from target_students ts where p_recipient_kind in ('student','both') and nullif(trim(ts.phone),'') is not null
    union all
    select ts.id,ts.name,g.name,g.phone,'guardian'::text
    from target_students ts join public.student_guardians sg on sg.student_id=ts.id join public.guardians g on g.id=sg.guardian_id
    where p_recipient_kind in ('guardian','both') and nullif(trim(g.phone),'') is not null
  ), deduplicated as (
    select distinct on (regexp_replace(phone,'[^0-9]','','g')) student_id,student_name,recipient_name,phone,kind
    from recipients order by regexp_replace(phone,'[^0-9]','','g'),student_name,kind
  )
  select case when public.is_staff() then coalesce(jsonb_agg(jsonb_build_object(
    'studentId',student_id,'studentName',student_name,'recipientName',recipient_name,
    'phone',left(phone,3)||'-****-'||right(phone,4),'kind',kind
  ) order by student_name,kind),'[]'::jsonb) else '[]'::jsonb end from deduplicated
$$;

create or replace function public.staff_queue_selected_messages(p_student_ids uuid[], p_recipient_kind text, p_body text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare queued_count integer;
begin
  if not public.is_staff() then raise exception '교직원만 문자를 발송 대기열에 등록할 수 있습니다.'; end if;
  if coalesce(array_length(p_student_ids,1),0)=0 then raise exception '발송할 학생을 선택해 주세요.'; end if;
  if array_length(p_student_ids,1)>500 then raise exception '한 번에 최대 500명까지 선택할 수 있습니다.'; end if;
  if p_recipient_kind not in ('student','guardian','both') then raise exception '수신자 유형을 선택해 주세요.'; end if;
  if nullif(trim(p_body),'') is null then raise exception '문자 내용을 입력해 주세요.'; end if;

  with target_students as (
    select distinct s.id,s.name,s.phone from public.students s
    where s.status in ('active','재원') and s.id=any(p_student_ids)
  ), recipients as (
    select ts.id student_id,ts.name recipient_name,ts.phone from target_students ts
    where p_recipient_kind in ('student','both') and nullif(trim(ts.phone),'') is not null
    union all
    select ts.id,g.name,g.phone from target_students ts join public.student_guardians sg on sg.student_id=ts.id join public.guardians g on g.id=sg.guardian_id
    where p_recipient_kind in ('guardian','both') and nullif(trim(g.phone),'') is not null
  ), deduplicated as (
    select distinct on (regexp_replace(phone,'[^0-9]','','g')) student_id,recipient_name,phone
    from recipients order by regexp_replace(phone,'[^0-9]','','g'),student_id
  )
  insert into public.message_logs(student_id,recipient_name,recipient_phone,message_type,body,provider,status)
  select student_id,recipient_name,phone,'manual',trim(p_body),'pending','pending_approval' from deduplicated;
  get diagnostics queued_count=row_count;
  return queued_count;
end
$$;

revoke all on function public.staff_message_target_options() from public;
revoke all on function public.staff_message_recipient_preview_selected(uuid[],text) from public;
revoke all on function public.staff_queue_selected_messages(uuid[],text,text) from public;
grant execute on function public.staff_message_target_options() to authenticated;
grant execute on function public.staff_message_recipient_preview_selected(uuid[],text) to authenticated;
grant execute on function public.staff_queue_selected_messages(uuid[],text,text) to authenticated;
