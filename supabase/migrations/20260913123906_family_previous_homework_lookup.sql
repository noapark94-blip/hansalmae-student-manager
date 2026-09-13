-- Read only. Validate the current record and student ownership before looking backwards.
create or replace function public.family_previous_homework(p_student_id uuid,p_record_id uuid,p_kind text)
returns text language plpgsql stable security definer set search_path=public
as $function$
declare selected_id uuid; current_row record; result text;
begin
 selected_id := public.internal_family_student_id(p_student_id);
 if selected_id is null then raise exception '연결된 학생의 기록만 확인할 수 있습니다.'; end if;
 if p_kind='correction' then
  select r.* into current_row from public.correction_reports r where r.id=p_record_id and r.student_id=selected_id and r.published and r.correction_date<=current_date;
  if not found then raise exception '공개된 첨삭 기록만 확인할 수 있습니다.'; end if;
  select r.homework_instruction into result from public.correction_reports r
  where r.student_id=selected_id and r.published and r.subject=current_row.subject
   and (r.correction_date,r.start_time)<(current_row.correction_date,current_row.start_time)
   and nullif(trim(r.homework_instruction),'') is not null
  order by r.correction_date desc,r.start_time desc,r.id desc limit 1;
 elsif p_kind='lesson' then
  select l.* into current_row from public.lessons l where l.id=p_record_id and l.status='completed' and l.lesson_date<=current_date
   and exists(select 1 from public.attendance a where a.lesson_id=l.id and a.student_id=selected_id);
  if found then
   select coalesce(hr.assigned_homework,l.homework_content,'') into result
   from public.lessons l left join public.lesson_homework_results hr on hr.lesson_id=l.id and hr.student_id=selected_id
   where l.class_id=current_row.class_id and l.status='completed' and l.starts_at<current_row.starts_at and l.lesson_date<=current_date
    and exists(select 1 from public.attendance a where a.lesson_id=l.id and a.student_id=selected_id)
    and nullif(trim(coalesce(hr.assigned_homework,l.homework_content,'')),'') is not null
   order by l.starts_at desc,l.id desc limit 1;
  else
   select l.* into current_row from public.teacher_special_lessons l where l.id=p_record_id and l.status='completed' and l.lesson_date<=current_date
    and exists(select 1 from public.teacher_special_lesson_students a where a.session_id=l.id and a.student_id=selected_id);
   if not found then raise exception '공개된 수업 기록만 확인할 수 있습니다.'; end if;
   select a.assigned_homework into result
   from public.teacher_special_lessons l join public.teacher_special_lesson_students a on a.session_id=l.id and a.student_id=selected_id
   where l.status='completed' and l.kind=current_row.kind and l.subject_id is not distinct from current_row.subject_id
    and l.teacher_profile_id is not distinct from current_row.teacher_profile_id
    and (l.lesson_date,l.starts_at)<(current_row.lesson_date,current_row.starts_at)
    and nullif(trim(a.assigned_homework),'') is not null
   order by l.lesson_date desc,l.starts_at desc,l.id desc limit 1;
  end if;
 else raise exception '지원하지 않는 기록 종류입니다.';
 end if;
 return coalesce(trim(result),'');
end $function$;
revoke all on function public.family_previous_homework(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.family_previous_homework(uuid,uuid,text) to authenticated;
