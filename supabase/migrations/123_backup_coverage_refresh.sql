-- 초기 백업 화면의 고정 범위를 현재 운영 테이블 전체로 갱신합니다.
create or replace function public.admin_backup_dashboard()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare
  allowed text[]:=array['students','classes','learning','operations','billing','communications'];
  group_name text; table_name text; tables text[]; table_count bigint; section_count bigint;
  result_counts jsonb:='{}'::jsonb; result_table_counts jsonb:='{}'::jsonb;
begin
  if public.current_user_role()<>'admin' then return jsonb_build_object('error','관리자만 백업 현황을 확인할 수 있습니다.'); end if;
  foreach group_name in array allowed loop
    tables:=case group_name
      when 'students' then array['students','guardians','student_guardians','student_status_history','academy_schools','bulk_import_logs']
      when 'classes' then array['profiles','account_change_logs','classes','class_schedules','class_teachers','enrollments','teachers','academy_subjects','student_schedule_assignments','user_ui_preferences','app_menu_settings','account_invites','bulk_account_import_logs']
      when 'learning' then array['lessons','attendance','attendance_status_history','makeup_sessions','assignments','assignment_submissions','consultations','exam_categories','lesson_exam_results','lesson_homework_results','class_daily_notices','class_makeup_attendees','teacher_special_lessons','teacher_special_lesson_students','teacher_special_lesson_exam_results','family_learning_report_reads','family_special_lesson_report_reads']
      when 'operations' then array['correction_assignments','correction_exceptions','correction_slot_capacities','correction_schedule_exceptions','correction_reports','correction_report_reads','vehicle_runs','vehicle_boardings','vehicle_run_exceptions','vehicle_schedule_exclusions','vehicle_manual_assignments','schedule_exceptions']
      when 'billing' then array['tuition_charges','tuition_payments','tuition_recurring_adjustments','tuition_fee_groups','tuition_subject_group_mappings','tuition_combination_discounts']
      when 'communications' then array['announcements','announcement_read_receipts','message_logs','family_notifications']
    end;
    section_count:=0;
    foreach table_name in array tables loop
      execute format('select count(*) from public.%I',table_name) into table_count;
      section_count:=section_count+table_count;
    end loop;
    result_counts:=result_counts||jsonb_build_object(group_name,section_count);
    result_table_counts:=result_table_counts||jsonb_build_object(group_name,cardinality(tables));
  end loop;
  return jsonb_build_object(
    'counts',result_counts,'tableCounts',result_table_counts,
    'recentLogs',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'action',l.action,'section',l.section,'recordCount',l.record_count,'createdAt',l.created_at,'requestedBy',p.display_name) order by l.created_at desc) from (select * from public.backup_audit_logs order by created_at desc limit 15) l join public.profiles p on p.id=l.requested_by),'[]'::jsonb)
  );
end;
$$;

create or replace function public.admin_export_backup(p_section text default 'all',p_format text default 'json')
returns jsonb language plpgsql volatile security definer set search_path=public as $$
declare
  allowed text[]:=array['students','classes','learning','operations','billing','communications']; selected text[];
  group_name text; table_name text; tables text[]; table_rows jsonb; result_data jsonb:='{}'::jsonb;
  total_count integer:=0; total_tables integer:=0;
begin
  if public.current_user_role()<>'admin' then raise exception '관리자만 백업을 생성할 수 있습니다.'; end if;
  if p_section<>'all' and not (p_section=any(allowed)) then raise exception '지원하지 않는 백업 구분입니다.'; end if;
  if p_format not in ('json','csv') then raise exception '지원하지 않는 내보내기 형식입니다.'; end if;
  selected:=case when p_section='all' then allowed else array[p_section] end;
  foreach group_name in array selected loop
    tables:=case group_name
      when 'students' then array['students','guardians','student_guardians','student_status_history','academy_schools','bulk_import_logs']
      when 'classes' then array['profiles','account_change_logs','classes','class_schedules','class_teachers','enrollments','teachers','academy_subjects','student_schedule_assignments','user_ui_preferences','app_menu_settings','account_invites','bulk_account_import_logs']
      when 'learning' then array['lessons','attendance','attendance_status_history','makeup_sessions','assignments','assignment_submissions','consultations','exam_categories','lesson_exam_results','lesson_homework_results','class_daily_notices','class_makeup_attendees','teacher_special_lessons','teacher_special_lesson_students','teacher_special_lesson_exam_results','family_learning_report_reads','family_special_lesson_report_reads']
      when 'operations' then array['correction_assignments','correction_exceptions','correction_slot_capacities','correction_schedule_exceptions','correction_reports','correction_report_reads','vehicle_runs','vehicle_boardings','vehicle_run_exceptions','vehicle_schedule_exclusions','vehicle_manual_assignments','schedule_exceptions']
      when 'billing' then array['tuition_charges','tuition_payments','tuition_recurring_adjustments','tuition_fee_groups','tuition_subject_group_mappings','tuition_combination_discounts']
      when 'communications' then array['announcements','announcement_read_receipts','message_logs','family_notifications']
    end;
    foreach table_name in array tables loop
      execute format('select coalesce(jsonb_agg(to_jsonb(t)),''[]''::jsonb) from public.%I t',table_name) into table_rows;
      result_data:=result_data||jsonb_build_object(table_name,table_rows);
      total_count:=total_count+jsonb_array_length(table_rows); total_tables:=total_tables+1;
    end loop;
  end loop;
  insert into public.backup_audit_logs(requested_by,action,section,record_count)
  values(auth.uid(),case when p_format='csv' then 'export_csv' else 'export_json' end,p_section,total_count);
  return jsonb_build_object('metadata',jsonb_build_object('app','hansalmae-student-manager','version',2,'coverageVersion',123,'exportedAt',now(),'section',p_section,'recordCount',total_count,'tableCount',total_tables),'data',result_data);
end;
$$;

revoke all on function public.admin_backup_dashboard() from public;
revoke all on function public.admin_export_backup(text,text) from public;
grant execute on function public.admin_backup_dashboard() to authenticated;
grant execute on function public.admin_export_backup(text,text) to authenticated;
