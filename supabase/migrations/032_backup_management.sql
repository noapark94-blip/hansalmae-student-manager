-- 관리자 전용 데이터 내보내기와 백업 이력을 제공합니다.
create table if not exists public.backup_audit_logs (
  id uuid primary key default gen_random_uuid(),
  requested_by uuid not null references public.profiles(id) on delete restrict,
  action text not null check (action in ('export_json','export_csv','validate_restore')),
  section text not null,
  record_count integer not null default 0 check (record_count >= 0),
  created_at timestamptz not null default now()
);

alter table public.backup_audit_logs enable row level security;
create policy "admin_read_backup_logs" on public.backup_audit_logs for select to authenticated using (public.current_user_role()='admin');
revoke all on public.backup_audit_logs from anon, authenticated;
grant select on public.backup_audit_logs to authenticated;

create or replace function public.admin_backup_dashboard()
returns jsonb language sql stable security definer set search_path=public as $$
  select case when public.current_user_role()<>'admin' then
    (select jsonb_build_object('error','관리자만 백업 현황을 확인할 수 있습니다.'))
  else jsonb_build_object(
    'counts',jsonb_build_object(
      'students',(select count(*) from public.students),
      'classes',(select count(*) from public.classes),
      'learning',(select count(*) from public.attendance)+(select count(*) from public.assignments)+(select count(*) from public.consultations),
      'operations',(select count(*) from public.correction_assignments)+(select count(*) from public.vehicle_runs),
      'billing',(select count(*) from public.tuition_charges)+(select count(*) from public.tuition_payments),
      'communications',(select count(*) from public.announcements)+(select count(*) from public.message_logs)+(select count(*) from public.family_notifications)
    ),
    'recentLogs',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'action',l.action,'section',l.section,'recordCount',l.record_count,'createdAt',l.created_at,'requestedBy',p.display_name) order by l.created_at desc) from (select * from public.backup_audit_logs order by created_at desc limit 15) l join public.profiles p on p.id=l.requested_by),'[]'::jsonb)
  ) end;
$$;

create or replace function public.admin_export_backup(p_section text default 'all',p_format text default 'json')
returns jsonb language plpgsql volatile security definer set search_path=public as $$
declare
  allowed text[]:=array['students','classes','learning','operations','billing','communications'];
  selected text[];
  group_name text;
  table_name text;
  tables text[];
  table_rows jsonb;
  result_data jsonb:='{}'::jsonb;
  total_count integer:=0;
begin
  if public.current_user_role()<>'admin' then raise exception '관리자만 백업을 생성할 수 있습니다.'; end if;
  if p_section<>'all' and not (p_section=any(allowed)) then raise exception '지원하지 않는 백업 구분입니다.'; end if;
  if p_format not in ('json','csv') then raise exception '지원하지 않는 내보내기 형식입니다.'; end if;
  selected:=case when p_section='all' then allowed else array[p_section] end;

  foreach group_name in array selected loop
    tables:=case group_name
      when 'students' then array['students','guardians','student_guardians','student_status_history']
      when 'classes' then array['profiles','account_change_logs','classes','class_schedules','class_teachers','enrollments','teachers']
      when 'learning' then array['lessons','attendance','attendance_status_history','makeup_sessions','assignments','assignment_submissions','consultations']
      when 'operations' then array['correction_assignments','correction_exceptions','correction_slot_capacities','vehicle_runs','vehicle_boardings','vehicle_run_exceptions','schedule_exceptions']
      when 'billing' then array['tuition_charges','tuition_payments','tuition_recurring_adjustments']
      when 'communications' then array['announcements','message_logs','family_notifications']
    end;
    foreach table_name in array tables loop
      execute format('select coalesce(jsonb_agg(to_jsonb(t)),''[]''::jsonb) from public.%I t',table_name) into table_rows;
      result_data:=result_data||jsonb_build_object(table_name,table_rows);
      total_count:=total_count+jsonb_array_length(table_rows);
    end loop;
  end loop;

  insert into public.backup_audit_logs(requested_by,action,section,record_count)
  values(auth.uid(),case when p_format='csv' then 'export_csv' else 'export_json' end,p_section,total_count);
  return jsonb_build_object('metadata',jsonb_build_object('app','hansalmae-student-manager','version',1,'exportedAt',now(),'section',p_section,'recordCount',total_count),'data',result_data);
end $$;

create or replace function public.admin_log_restore_validation(p_record_count integer)
returns void language plpgsql volatile security definer set search_path=public as $$
begin
  if public.current_user_role()<>'admin' then raise exception '관리자만 복원 파일을 검증할 수 있습니다.'; end if;
  insert into public.backup_audit_logs(requested_by,action,section,record_count) values(auth.uid(),'validate_restore','all',greatest(p_record_count,0));
end $$;

revoke all on function public.admin_backup_dashboard() from public;
revoke all on function public.admin_export_backup(text,text) from public;
revoke all on function public.admin_log_restore_validation(integer) from public;
grant execute on function public.admin_backup_dashboard() to authenticated;
grant execute on function public.admin_export_backup(text,text) to authenticated;
grant execute on function public.admin_log_restore_validation(integer) to authenticated;
