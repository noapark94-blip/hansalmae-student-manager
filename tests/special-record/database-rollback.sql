begin;
do $$
declare sid uuid; teacher uuid; student text; snap jsonb; first_snap jsonb; result jsonb; old jsonb;
begin
 select l.id,l.teacher_profile_id into sid,teacher from public.teacher_special_lessons l where exists(select 1 from public.teacher_special_lesson_students where session_id=l.id) limit 1;
 if sid is null then raise exception 'No fixture'; end if;
 perform set_config('request.jwt.claim.sub',teacher::text,true);
 snap:=public.staff_special_edit_snapshot(sid);
 select key into student from jsonb_each(snap->'values'->'students') limit 1;
 result:=public.staff_patch_special_record(sid,jsonb_build_array(jsonb_build_object('path',jsonb_build_array('students',student,'lessonContent'),'before',snap#>array['values','students',student,'lessonContent'],'value','conflict-test-A')),snap->>'state','draft');
 if result#>>array['values','students',student,'lessonContent'] <> 'conflict-test-A' then raise exception 'save failed'; end if;
 first_snap:=result;
 begin
  perform public.staff_patch_special_record(sid,jsonb_build_array(jsonb_build_object('path',jsonb_build_array('students',student,'lessonContent'),'before',snap#>array['values','students',student,'lessonContent'],'value','conflict-test-B')),'draft','draft');
  raise exception 'UNEXPECTED_OVERWRITE';
 exception when others then if sqlerrm not like '다른 선생님이 먼저%' then raise; end if; end;
 result:=public.staff_patch_special_record(sid,jsonb_build_array(jsonb_build_object('path',jsonb_build_array('students',student,'assignedHomework'),'before',snap#>array['values','students',student,'assignedHomework'],'value','independent-field')),'draft','draft');
 if result#>>array['values','students',student,'lessonContent'] <> 'conflict-test-A' then raise exception 'unrelated edit lost'; end if;
 -- Completion failure must roll back the learning write inside the same RPC.
 perform public.staff_save_special_lesson_attendance(sid,student::uuid,null,null,null);
 snap:=public.staff_special_edit_snapshot(sid);
 begin
  perform public.staff_patch_special_record(sid,jsonb_build_array(jsonb_build_object('path',jsonb_build_array('students',student,'lessonContent'),'before',snap#>array['values','students',student,'lessonContent'],'value','must-rollback')),'draft','completed');
  raise exception 'UNEXPECTED_COMPLETION';
 exception when others then if sqlerrm not like '출결 미입력 학생:%' then raise; end if; end;
 result:=public.staff_special_edit_snapshot(sid);
 if result#>>array['values','students',student,'lessonContent'] <> 'conflict-test-A' or result->>'state'<>'draft' then raise exception 'partial write escaped'; end if;
 -- Attendance patches use the same stale-value check.
 result:=public.staff_patch_special_record(sid,jsonb_build_array(jsonb_build_object('path',jsonb_build_array('students',student,'status'),'before',null,'value','present')),'draft','attendance');
 begin
  perform public.staff_patch_special_record(sid,jsonb_build_array(jsonb_build_object('path',jsonb_build_array('students',student,'status'),'before',null,'value','absent')),'draft','attendance');
  raise exception 'UNEXPECTED_ATTENDANCE_OVERWRITE';
 exception when others then if sqlerrm not like '다른 선생님이 먼저%' then raise; end if; end;
 perform set_config('request.jwt.claim.sub','',true);
 begin perform public.staff_patch_special_record(sid,'[]','draft','draft');raise exception 'UNEXPECTED_ANON';exception when others then if sqlerrm<>'교직원만 저장할 수 있습니다.' then raise;end if;end;
end $$;
select 'special record conflicts, independent edits, attendance conflicts, atomic failure, anonymous denial passed' as result;
rollback;
