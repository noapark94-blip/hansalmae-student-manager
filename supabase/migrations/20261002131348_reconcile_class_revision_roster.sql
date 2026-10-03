CREATE OR REPLACE FUNCTION public.staff_class_edit_snapshot(p_class_id uuid, p_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare ex jsonb; hw jsonb; dy jsonb; rv jsonb; nt text; lc text; payload jsonb; st text;
begin
 if auth.uid() is null or not public.is_staff() or
   (public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid())) then
  raise exception '담당 클래스만 확인할 수 있습니다.';
 end if;
 ex:=public.staff_class_exam_results(p_class_id,p_date);
 hw:=public.staff_class_homework_results(p_class_id,p_date);
 dy:=public.staff_class_day(p_class_id,p_date);
 rv:=public.staff_class_revision_draft(p_class_id,p_date);
 nt:=public.staff_class_daily_notice(p_class_id,p_date);
 lc:=public.staff_class_lesson_content(p_class_id,p_date);
 select case when status='completed' then 'completed' else 'draft' end into st from public.lessons
  where class_id=p_class_id and lesson_date=p_date and id=public.internal_class_record_lesson_id(p_class_id,p_date)
  order by starts_at limit 1;
 select jsonb_build_object('notice',coalesce(nt,''),'lessonContent',coalesce(lc,''),'rows',coalesce(jsonb_agg(
  s||jsonb_build_object('studentId',s->>'id','status',case when s->>'status'='excused' then to_jsonb('absent'::text) else s->'status' end,
   'lessonContent',h->>'lessonContent','assignedHomework',h->>'assignedHomework','inspectionStatus',h->>'inspectionStatus','inspectionNote',h->>'inspectionNote',
   'exam',coalesce(e->'exams'->0,'{}'))),'[]')) into payload
 from jsonb_array_elements(coalesce(dy->'students','[]')) s
 left join jsonb_array_elements(coalesce(ex,'[]')) e on e->>'studentId'=s->>'id'
 left join jsonb_array_elements(coalesce(hw,'[]')) h on h->>'studentId'=s->>'id';
 -- A saved revision can predate enrollment changes or contain no rows after deletion.
 -- Use the current day roster, overlaying only matching private draft rows.
 -- Read-only reconciliation: never discard or publish the stored revision here.
 if jsonb_typeof(rv->'payload')='object' then
  payload:=jsonb_build_object(
   'notice',coalesce(rv#>'{payload,notice}',payload->'notice'),
   'lessonContent',coalesce(rv#>'{payload,lessonContent}',payload->'lessonContent'),
   'rows',coalesce((select jsonb_agg(live_row || coalesce((
    select draft_row from jsonb_array_elements(coalesce(rv#>'{payload,rows}','[]')) draft_row
    where draft_row->>'studentId'=live_row->>'studentId' limit 1
   ),'{}'::jsonb) order by ordinal)
   from jsonb_array_elements(payload->'rows') with ordinality live(live_row,ordinal)),'[]'::jsonb));
 end if;
 return jsonb_build_object('exams',ex,'homework',hw,'day',dy,'notice',nt,'lessonContent',lc,'revision',rv,
  'state',coalesce(st,'draft'),'values',public.class_edit_values(payload));
end $function$;

