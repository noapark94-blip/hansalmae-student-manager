-- Compact source references only; no backfill or changes to student learning records.
alter table public.learning_alimtalk_deliveries add column source_refs jsonb;
create function public.internal_alimtalk_source_refs(p_rows jsonb)
returns jsonb language sql immutable set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object(
  'lessonId',r->>'lessonId','source',r->>'source','subject',r->>'subject',
  'lessonDate',r->>'lessonDate','className',r->>'className',
  'exam',coalesce(jsonb_array_length(r->'exams'),0)>0 or coalesce(r->>'examContent','')<>'',
  'homework',coalesce(r->>'homeworkContent','')<>'',
  'correction',r->>'source'='correction'
 )), '[]'::jsonb) from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) r
$$;
revoke all on function public.internal_alimtalk_source_refs(jsonb) from public,anon,authenticated;
create function public.internal_capture_alimtalk_source_refs()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 new.source_refs:=public.internal_alimtalk_source_refs(public.staff_learning_report_source(new.student_id,new.period_start,new.period_end));
 return new;
end $$;
revoke all on function public.internal_capture_alimtalk_source_refs() from public,anon,authenticated;
create trigger capture_alimtalk_source_refs before insert or update of template_variables,student_id,period_start,period_end
 on public.learning_alimtalk_deliveries for each row execute function public.internal_capture_alimtalk_source_refs();

create function public.staff_alimtalk_record_links(p_delivery_id uuid default null,p_student_id uuid default null,p_from date default null,p_to date default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
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
end $$;
revoke all on function public.staff_alimtalk_record_links(uuid,uuid,date,date) from public,anon;
grant execute on function public.staff_alimtalk_record_links(uuid,uuid,date,date) to authenticated;
