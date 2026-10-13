-- Keep multiline overlap warnings in the JSON body, not the HTTP reason phrase.
create or replace function public.staff_save_mixed_special_lesson(p_values jsonb,p_reminder_enabled boolean,p_students jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare sid uuid; old_id uuid:=nullif(p_values->>'p_id','')::uuid;
 teacher uuid:=coalesce(nullif(p_values->>'p_teacher_id','')::uuid,auth.uid());
 d date:=(p_values->>'p_date')::date; st time:=(p_values->>'p_start_time')::time; en time:=(p_values->>'p_end_time')::time;
 item record; msg text; warnings text[]:='{}'; warning_text text; token text; previous text;
begin
 if auth.uid() is null or not coalesce(public.is_staff(),false) or (public.current_user_role()<>'admin' and teacher<>auth.uid()) then raise exception '저장 권한이 없습니다.'; end if;
 if old_id is not null and not exists(select 1 from teacher_special_lessons where id=old_id and (teacher_profile_id=auth.uid() or public.current_user_role()='admin')) then raise exception '수정 권한이 없습니다.'; end if;
 if jsonb_typeof(p_students) is distinct from 'array' or jsonb_array_length(p_students)=0 or d is null or st is null or en is null or en<=st then raise exception '학생과 수업 시간을 확인해 주세요.'; end if;
 perform pg_advisory_xact_lock(hashtextextended('mixed-special-lessons',0));
 if exists(select 1 from teacher_special_lessons l join teacher_special_lesson_students ss on ss.session_id=l.id
 where l.id is distinct from old_id and l.lesson_date=d and l.starts_at=st and l.ends_at=en and l.subject_id=nullif(p_values->>'p_subject_id','')::uuid
 and exists(select 1 from jsonb_array_elements(p_students) s where s->>'studentId'=ss.student_id::text)) then
 raise exception '같은 학생·과목·시간의 보강 또는 추가수업이 이미 등록되어 있습니다.'; end if;
 for item in select s.id,s.name from students s where exists(select 1 from jsonb_array_elements(p_students) x where x->>'studentId'=s.id::text) order by s.id loop
 msg:=public.student_date_conflict_message(item.id,d,st,en,old_id,null,null);
 if msg is not null then warnings:=array_append(warnings,item.name||' 학생 · '||msg); end if;
 end loop;
 for item in
 select c.name title,cs.start_time starts,cs.end_time ends from class_schedules cs join classes c on c.id=cs.class_id join class_teachers ct on ct.class_id=c.id
 where ct.profile_id=teacher and c.active and cs.weekday=extract(isodow from d) and (cs.valid_from is null or cs.valid_from<=d) and (cs.valid_until is null or cs.valid_until>=d) and cs.start_time<en and cs.end_time>st
 and not exists(select 1 from schedule_exceptions x where x.class_id=c.id and x.original_date=d and x.kind='cancelled')
 union all select coalesce(a.name,'보강·추가수업'),l.starts_at,l.ends_at from teacher_special_lessons l left join academy_subjects a on a.id=l.subject_id where l.teacher_profile_id=teacher and l.id is distinct from old_id and l.lesson_date=d and l.starts_at<en and l.ends_at>st
 order by starts,title
 loop warnings:=array_append(warnings,coalesce((select display_name from profiles where id=teacher),'담당')||' 선생님 · '||item.title||' '||to_char(item.starts,'HH24:MI')||'–'||to_char(item.ends,'HH24:MI')); end loop;
 warning_text:=array_to_string(warnings,E'\n');
 token:=md5(jsonb_build_array(p_values-'p_overlap_token',p_students,p_reminder_enabled,warnings)::text);
 if cardinality(warnings)>0 and (p_values->>'p_overlap_token') is distinct from token then
 raise sqlstate 'PGRST' using
   message=jsonb_build_object('code','PT409','message',warning_text,'details',token)::text,
   detail=jsonb_build_object('status',409,'headers','{}'::jsonb)::text; end if;
 previous:=current_setting('app.special_overlap_actor',true);
 perform set_config('app.special_overlap_actor',case when cardinality(warnings)>0 then auth.uid()::text else '' end,true);
 sid:=public.internal_save_mixed_special_lesson(p_values,p_reminder_enabled,p_students);
 perform set_config('app.special_overlap_actor',coalesce(previous,''),true);
 update teacher_special_lessons set overlap_notice=nullif(warning_text,'') where id=sid;
 return sid;
end $$;
revoke all on function public.staff_save_mixed_special_lesson(jsonb,boolean,jsonb) from public,anon;
grant execute on function public.staff_save_mixed_special_lesson(jsonb,boolean,jsonb) to authenticated;
