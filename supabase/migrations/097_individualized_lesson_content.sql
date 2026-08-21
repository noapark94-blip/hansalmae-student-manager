-- 학생별 수업 내용: 기존 숙제 결과 행을 확장해 같은 수업/학생 단위로 저장합니다.
alter table public.lesson_homework_results
  add column if not exists lesson_content text;

create or replace function public.staff_class_homework_results(p_class_id uuid,p_date date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if not public.is_staff() then raise exception '교직원만 숙제 결과를 확인할 수 있습니다.'; end if;
  if public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid()) then raise exception '담당 클래스만 확인할 수 있습니다.'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('studentId',s.id,'lessonContent',coalesce(current_result.lesson_content,''),'assignedHomework',coalesce(current_result.assigned_homework,''),'inspectionStatus',coalesce(current_result.inspection_status,current_result.status,''),'inspectionNote',coalesce(current_result.inspection_note,current_result.note,''),'previousHomework',coalesce(previous_result.assigned_homework,'')) order by s.name),'[]'::jsonb) into result
  from public.enrollments e join public.students s on s.id=e.student_id
  left join lateral(select id from public.lessons where class_id=p_class_id and lesson_date=p_date order by starts_at limit 1) lesson on true
  left join public.lesson_homework_results current_result on current_result.lesson_id=lesson.id and current_result.student_id=s.id
  left join lateral(select hr.assigned_homework from public.lesson_homework_results hr join public.lessons prior on prior.id=hr.lesson_id where prior.class_id=p_class_id and prior.lesson_date<p_date and hr.student_id=s.id and nullif(trim(hr.assigned_homework),'') is not null order by prior.lesson_date desc limit 1) previous_result on true
  where e.class_id=p_class_id and e.status='active' and public.student_attends_class_on(s.id,p_class_id,p_date);
  return result;
end $$;

create or replace function public.staff_save_class_homework_results(p_class_id uuid,p_date date,p_results jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare lesson uuid; item jsonb; sid uuid; individual_lesson text; assigned text; inspection text; inspection_memo text;
begin
  lesson:=public.staff_save_class_day(p_class_id,p_date,null,null,null);
  for item in select value from jsonb_array_elements(coalesce(p_results,'[]'::jsonb)) loop
    sid:=(item->>'studentId')::uuid; individual_lesson:=nullif(trim(item->>'lessonContent'),''); assigned:=nullif(trim(item->>'assignedHomework'),''); inspection:=nullif(item->>'inspectionStatus',''); inspection_memo:=nullif(trim(item->>'inspectionNote'),'');
    if inspection is not null and inspection not in ('complete','partial','missing','excused') then raise exception '숙제 검사 상태를 확인해 주세요.'; end if;
    if individual_lesson is null and assigned is null and inspection is null and inspection_memo is null then delete from public.lesson_homework_results where lesson_id=lesson and student_id=sid;
    else insert into public.lesson_homework_results(lesson_id,student_id,lesson_content,assigned_homework,inspection_status,inspection_note,status,note,created_by) values(lesson,sid,individual_lesson,assigned,inspection,inspection_memo,inspection,inspection_memo,auth.uid())
      on conflict(lesson_id,student_id) do update set lesson_content=excluded.lesson_content,assigned_homework=excluded.assigned_homework,inspection_status=excluded.inspection_status,inspection_note=excluded.inspection_note,status=excluded.status,note=excluded.note,updated_at=now(); end if;
  end loop;
end $$;

revoke all on function public.staff_class_homework_results(uuid,date),public.staff_save_class_homework_results(uuid,date,jsonb) from public,anon;
grant execute on function public.staff_class_homework_results(uuid,date),public.staff_save_class_homework_results(uuid,date,jsonb) to authenticated;

create or replace function public.staff_student_completed_learning_history(p_student_id uuid,p_limit integer default 300)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare raw_rows jsonb; result jsonb;
begin
  raw_rows:=public.staff_student_learning_history(p_student_id,p_limit);
  select coalesce(jsonb_agg(jsonb_set(entry.item,'{lessonContent}',to_jsonb(coalesce(nullif(trim(hr.lesson_content),''),entry.item->>'lessonContent',''))) order by entry.ord),'[]'::jsonb) into result
  from jsonb_array_elements(coalesce(raw_rows,'[]'::jsonb)) with ordinality entry(item,ord)
  join public.lessons l on l.id=(entry.item->>'lessonId')::uuid
  left join public.lesson_homework_results hr on hr.lesson_id=l.id and hr.student_id=p_student_id
  where l.status='completed' and jsonb_typeof(entry.item->'attendance')='object';
  return result;
end $$;

create or replace function public.family_completed_learning_reports(p_student_id uuid default null,p_limit integer default 10)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare raw_rows jsonb; result jsonb; selected_id uuid;
begin
  raw_rows:=public.family_learning_reports(p_student_id,p_limit);
  if public.current_user_role()='student' then select s.id into selected_id from public.students s where s.profile_id=auth.uid(); else selected_id:=p_student_id; end if;
  if selected_id is null and public.current_user_role()='guardian' then select s.id into selected_id from public.guardians g join public.student_guardians sg on sg.guardian_id=g.id join public.students s on s.id=sg.student_id where g.profile_id=auth.uid() order by sg.is_primary desc,s.name limit 1; end if;
  select coalesce(jsonb_agg(jsonb_set(entry.item,'{lessonContent}',to_jsonb(coalesce(nullif(trim(hr.lesson_content),''),entry.item->>'lessonContent',''))) order by entry.ord),'[]'::jsonb) into result
  from jsonb_array_elements(coalesce(raw_rows,'[]'::jsonb)) with ordinality entry(item,ord)
  join public.lessons l on l.id=(entry.item->>'lessonId')::uuid
  left join public.lesson_homework_results hr on hr.lesson_id=l.id and hr.student_id=selected_id
  where l.status='completed';
  return result;
end $$;

revoke all on function public.staff_student_completed_learning_history(uuid,integer),public.family_completed_learning_reports(uuid,integer) from public,anon;
grant execute on function public.staff_student_completed_learning_history(uuid,integer),public.family_completed_learning_reports(uuid,integer) to authenticated;
notify pgrst,'reload schema';
