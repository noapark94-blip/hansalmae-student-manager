-- Field-level optimistic concurrency. All public entry points retain class authorization.
create or replace function public.class_edit_values(p_payload jsonb)
returns jsonb language plpgsql immutable set search_path=public as $$
declare r jsonb; e jsonb; students jsonb:='{}'; v jsonb; k text;
begin
 for r in select value from jsonb_array_elements(coalesce(p_payload->'rows','[]')) loop
  e:=coalesce(r->'exam','{}');
  v:=jsonb_build_object('status',r->'status','lateMinutes',r->'lateMinutes',
    'absenceReason',coalesce(r->>'absenceReason',''),'note',coalesce(r->>'note',''));
  foreach k in array array['lessonContent','assignedHomework','inspectionStatus','inspectionNote'] loop
   v:=v||jsonb_build_object(k,coalesce(r->>k,''));
  end loop;
  foreach k in array array['id','examType','examTitle','score','evaluation','feedback'] loop
   v:=v||jsonb_build_object('exam_'||k,coalesce(e->>k,''));
  end loop;
  v:=v||jsonb_build_object('exam_maxScore',coalesce(nullif(e->>'maxScore',''),'100'));
  students:=students||jsonb_build_object(r->>'studentId',v);
 end loop;
 return jsonb_build_object('notice',coalesce(p_payload->>'notice',''),'lessonContent',coalesce(p_payload->>'lessonContent',''),'students',students);
end $$;
revoke all on function public.class_edit_values(jsonb) from public,anon,authenticated;

create or replace function public.staff_class_edit_snapshot(p_class_id uuid,p_date date)
returns jsonb language plpgsql stable security definer set search_path=public as $$
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
  where class_id=p_class_id and lesson_date=p_date order by starts_at limit 1;
 select jsonb_build_object('notice',coalesce(nt,''),'lessonContent',coalesce(lc,''),'rows',coalesce(jsonb_agg(
  s||jsonb_build_object('studentId',s->>'id','status',case when s->>'status'='excused' then to_jsonb('absent'::text) else s->'status' end,
   'lessonContent',h->>'lessonContent','assignedHomework',h->>'assignedHomework','inspectionStatus',h->>'inspectionStatus','inspectionNote',h->>'inspectionNote',
   'exam',coalesce(e->'exams'->0,'{}'))),'[]')) into payload
 from jsonb_array_elements(coalesce(dy->'students','[]')) s
 left join jsonb_array_elements(coalesce(ex,'[]')) e on e->>'studentId'=s->>'id'
 left join jsonb_array_elements(coalesce(hw,'[]')) h on h->>'studentId'=s->>'id';
 -- A private revision is a complete existing draft; keep its original display semantics.
 return jsonb_build_object('exams',ex,'homework',hw,'day',dy,'notice',nt,'lessonContent',lc,'revision',rv,
  'state',coalesce(st,'draft'),'values',public.class_edit_values(coalesce(rv->'payload',payload)));
end $$;
revoke all on function public.staff_class_edit_snapshot(uuid,date) from public,anon;
grant execute on function public.staff_class_edit_snapshot(uuid,date) to authenticated;

create or replace function public.class_merge_edit_changes(p_current jsonb,p_changes jsonb)
returns jsonb language plpgsql immutable set search_path=public as $$
declare c jsonb; path text[]; result jsonb:=p_current; seen text[]:='{}'; key text;
begin
 if jsonb_typeof(p_changes) is distinct from 'array' then raise exception '수정 항목을 확인해 주세요.'; end if;
 for c in select value from jsonb_array_elements(p_changes) loop
  if jsonb_typeof(c->'path') is distinct from 'array' or not(c?'before' and c?'value') then raise exception '수정 항목을 확인해 주세요.'; end if;
  select array_agg(value order by ord) into path from jsonb_array_elements_text(c->'path') with ordinality p(value,ord);
  if not ((array_length(path,1)=1 and path[1] in ('notice','lessonContent')) or
    (array_length(path,1)=3 and path[1]='students' and path[3] in ('status','lateMinutes','absenceReason','note','lessonContent','assignedHomework','inspectionStatus','inspectionNote','exam_id','exam_examType','exam_examTitle','exam_score','exam_maxScore','exam_evaluation'))) then
   raise exception '지원하지 않는 수정 항목입니다.';
  end if;
  key:=array_to_string(path,'/');
  if key=any(seen) then raise exception '중복 수정 항목입니다.'; end if;
  seen:=array_append(seen,key);
  if p_current#>path is null then raise exception '수업 명단이 변경됐습니다. 입력 내용을 보관한 뒤 최신 명단을 확인해 주세요.'; end if;
  if (p_current#>path) is distinct from (c->'before') and (p_current#>path) is distinct from (c->'value') then
   raise exception '다른 선생님이 먼저 같은 항목을 수정했습니다. 입력 내용은 유지됩니다. 최신 내용을 확인해 주세요. (%)',path[array_length(path,1)];
  end if;
  result:=jsonb_set(result,path,c->'value',false);
 end loop;
 return result;
end $$;
revoke all on function public.class_merge_edit_changes(jsonb,jsonb) from public,anon,authenticated;

create or replace function public.staff_patch_class_record(p_class_id uuid,p_date date,p_changes jsonb,p_expected_state text,p_mode text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare snap jsonb; current_values jsonb; merged jsonb; payload jsonb; r record; row_value jsonb; row_payload jsonb;
 rows_payload jsonb:='[]'; exams jsonb:='[]'; homework jsonb:='[]'; lesson_id uuid; before_row jsonb; k text; change_exam boolean; change_hw boolean;
begin
 if auth.uid() is null or not public.is_staff() or
   (public.current_user_role()<>'admin' and not exists(select 1 from public.class_teachers where class_id=p_class_id and profile_id=auth.uid())) then
  raise exception '담당 클래스만 수정할 수 있습니다.';
 end if;
 if p_mode not in ('draft','complete','revision','publish','attendance') or p_mode is null then raise exception '저장 방식을 확인해 주세요.'; end if;
 -- Serialize only this class/date, including the first save when no lesson row exists.
 perform pg_advisory_xact_lock(hashtextextended(p_class_id::text||':'||p_date::text,0));
 select id into lesson_id from public.lessons where class_id=p_class_id and lesson_date=p_date order by starts_at limit 1 for update;
 snap:=public.staff_class_edit_snapshot(p_class_id,p_date);
 if snap->>'state' is distinct from p_expected_state then raise exception '수업 완료 상태가 변경됐습니다. 입력 내용을 보관한 뒤 최신 기록을 확인해 주세요.'; end if;
 if (p_mode in ('revision','publish'))<>(p_expected_state='completed') then raise exception '수업 상태에 맞는 저장 버튼을 이용해 주세요.'; end if;
 current_values:=snap->'values';
 merged:=public.class_merge_edit_changes(current_values,p_changes);
 -- Identity is a dependency when changing an exam, not a user-editable field.
 if exists(select 1 from jsonb_array_elements(p_changes) c where c->'path'->>2='exam_id' and c->'before' is distinct from c->'value') then raise exception '시험 기록 식별자는 수정할 수 없습니다.'; end if;
 if p_mode='attendance' and exists(select 1 from jsonb_array_elements(p_changes) c where jsonb_array_length(c->'path')<>3 or c->'path'->>2 not in ('status','lateMinutes','absenceReason','note')) then raise exception '출결 항목만 저장할 수 있습니다.'; end if;
 for r in select * from jsonb_each(merged->'students') loop
  row_value:=r.value; before_row:=current_values->'students'->r.key;
  row_payload:=jsonb_build_object('studentId',r.key,'status',row_value->'status','lateMinutes',row_value->'lateMinutes',
   'absenceReason',row_value->>'absenceReason','note',row_value->>'note','lessonContent',row_value->>'lessonContent',
   'assignedHomework',row_value->>'assignedHomework','inspectionStatus',row_value->>'inspectionStatus','inspectionNote',row_value->>'inspectionNote',
   'exam',jsonb_build_object('id',nullif(row_value->>'exam_id',''),'examType',row_value->>'exam_examType','examTitle',row_value->>'exam_examTitle',
    'score',nullif(row_value->>'exam_score','')::numeric,'maxScore',coalesce(nullif(row_value->>'exam_maxScore','')::numeric,100),'evaluation',row_value->>'exam_evaluation','feedback',row_value->>'exam_feedback'));
  rows_payload:=rows_payload||jsonb_build_array(row_payload);
  if p_mode in ('revision','publish') or row_value=before_row then continue; end if;
  change_exam:=false; change_hw:=false;
  foreach k in array array['exam_examType','exam_examTitle','exam_score','exam_maxScore','exam_evaluation'] loop
   change_exam:=change_exam or row_value->k is distinct from before_row->k;
  end loop;
  foreach k in array array['lessonContent','assignedHomework','inspectionStatus','inspectionNote'] loop
   change_hw:=change_hw or row_value->k is distinct from before_row->k;
  end loop;
  if change_exam then exams:=exams||jsonb_build_array(jsonb_build_object('studentId',r.key,'exams',jsonb_build_array(row_payload->'exam'))); end if;
  if change_hw then homework:=homework||jsonb_build_array(row_payload-'exam'); end if;
  if row_value->'status' is distinct from before_row->'status' or row_value->'lateMinutes' is distinct from before_row->'lateMinutes'
    or row_value->'absenceReason' is distinct from before_row->'absenceReason' or row_value->'note' is distinct from before_row->'note' then
   if row_value->>'status' is null then perform public.staff_clear_class_attendance(p_class_id,p_date,r.key::uuid);
   else perform public.staff_save_class_attendance(p_class_id,p_date,r.key::uuid,(row_value->>'status')::public.attendance_status,
    nullif(row_value->>'lateMinutes','')::integer,nullif(row_value->>'absenceReason',''),nullif(row_value->>'note','')); end if;
  end if;
 end loop;
 payload:=jsonb_build_object('notice',merged->>'notice','lessonContent',merged->>'lessonContent','rows',rows_payload);
 if p_mode='revision' then perform public.staff_save_class_revision_draft(p_class_id,p_date,payload);
 elsif p_mode='publish' then perform public.staff_publish_class_revision(p_class_id,p_date,payload);
 else
  if jsonb_array_length(exams)>0 then perform public.staff_save_class_exam_results(p_class_id,p_date,exams); end if;
  if jsonb_array_length(homework)>0 then perform public.staff_save_class_homework_results(p_class_id,p_date,homework); end if;
  if merged->'notice' is distinct from current_values->'notice' then perform public.staff_save_class_daily_notice(p_class_id,p_date,merged->>'notice'); end if;
  if merged->'lessonContent' is distinct from current_values->'lessonContent' then perform public.staff_save_class_lesson_content(p_class_id,p_date,merged->>'lessonContent'); end if;
  if p_mode<>'attendance' then perform public.staff_set_class_lesson_state(p_class_id,p_date,case when p_mode='complete' then 'completed' else 'draft' end); end if;
 end if;
 return public.staff_class_edit_snapshot(p_class_id,p_date);
end $$;
revoke all on function public.staff_patch_class_record(uuid,date,jsonb,text,text) from public,anon;
grant execute on function public.staff_patch_class_record(uuid,date,jsonb,text,text) to authenticated;
