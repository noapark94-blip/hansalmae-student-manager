create or replace function public.can_manage_communications()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select role in ('admin','teacher','assistant','manager','sub_admin') and is_active
    from public.profiles
    where id = auth.uid()
  ), false)
$$;

create or replace function public.can_send_alimtalk()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select role in ('admin','sub_admin') and is_active
    from public.profiles
    where id = auth.uid()
  ), false)
$$;

revoke all on function public.can_manage_communications() from public, anon;
revoke all on function public.can_send_alimtalk() from public, anon;
grant execute on function public.can_manage_communications() to authenticated, service_role;
grant execute on function public.can_send_alimtalk() to authenticated, service_role;

do $migration$
declare
  function_name text;
  function_definition text;
begin
  foreach function_name in array array[
    'communication_board',
    'staff_message_approval_board',
    'staff_announcement_read_overview',
    'staff_delete_announcement',
    'staff_delete_message_logs',
    'staff_message_recipient_preview_selected',
    'staff_message_target_options',
    'staff_queue_selected_messages',
    'staff_save_announcement',
    'staff_claim_message_delivery'
  ]
  loop
    for function_definition in
      select pg_get_functiondef(p.oid)
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = function_name
    loop
      execute replace(function_definition, 'public.is_staff()', 'public.can_manage_communications()');
    end loop;
  end loop;
end
$migration$;

do $migration$
declare
  function_name text;
  function_definition text;
begin
  foreach function_name in array array[
    'staff_alimtalk_recipient',
    'staff_claim_learning_alimtalk',
    'staff_alimtalk_ready_students',
    'staff_prepare_learning_alimtalk_resend'
  ]
  loop
    for function_definition in
      select pg_get_functiondef(p.oid)
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = function_name
    loop
      execute replace(function_definition, 'public.current_user_role()<>''admin''', 'not public.can_send_alimtalk()');
    end loop;
  end loop;

  select pg_get_functiondef(p.oid) into function_definition
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='staff_alimtalk_delivery_list';
  execute replace(function_definition, 'public.current_user_role()=''admin''', 'public.can_send_alimtalk()');

  select pg_get_functiondef(p.oid) into function_definition
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='staff_student_learning_history';
  execute replace(function_definition, 'not in (''admin'',''teacher'')', 'not in (''admin'',''teacher'',''sub_admin'')');

  select pg_get_functiondef(p.oid) into function_definition
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='staff_student_completed_learning_history';
  execute replace(function_definition, 'if not public.is_staff() then', 'if not public.is_staff() and not public.can_send_alimtalk() then');

  select pg_get_functiondef(p.oid) into function_definition
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='staff_learning_report_source';
  function_definition := replace(
    function_definition,
    'if not public.can_staff_report_student(p_student_id) then',
    'if not (public.can_staff_report_student(p_student_id) or public.can_send_alimtalk()) then'
  );
  function_definition := replace(
    function_definition,
    'public.current_user_role()=''admin'' or ca.teacher_profile_id=auth.uid()',
    'public.can_send_alimtalk() or ca.teacher_profile_id=auth.uid()'
  );
  execute function_definition;
end
$migration$;
