-- A sub administrator is a teacher-capable vice-director with additional
-- messaging access. Keep every role guard on that shared contract.
do $migration$
declare
  target record;
  original_definition text;
  updated_definition text;
begin
  for target in
    select p.oid, p.proname
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname in (
        'require_staff_profile',
        'correction_slot_assistant_board',
        'staff_save_correction_slot_assistants',
        'admin_update_account',
        'admin_set_teacher_classes',
        'staff_class_lesson_history',
        'delete_report_comment',
        'admin_permanently_delete_class'
      )
  loop
    original_definition:=pg_get_functiondef(target.oid);
    updated_definition:=original_definition;

    if target.proname='require_staff_profile' then
      updated_definition:=replace(updated_definition,
        'array[''admin'',''teacher'',''assistant'']',
        'array[''admin'',''sub_admin'',''teacher'',''assistant'']');
      updated_definition:=replace(updated_definition,
        'array[''admin'',''teacher'']',
        'array[''admin'',''sub_admin'',''teacher'']');
      updated_definition:=replace(updated_definition,
        '활성 관리자·선생님·조교 계정만 첨삭 담당자로 배정할 수 있습니다.',
        '활성 관리자·부관리자·선생님·조교 계정만 첨삭 담당자로 배정할 수 있습니다.');
      updated_definition:=replace(updated_definition,
        '로그인한 관리자 또는 선생님 계정만 담당자로 배정할 수 있습니다.',
        '로그인한 관리자·부관리자·선생님 계정만 담당자로 배정할 수 있습니다.');
    elsif target.proname in ('correction_slot_assistant_board','staff_save_correction_slot_assistants') then
      updated_definition:=replace(updated_definition,
        '(''admin'', ''teacher'', ''assistant'')',
        '(''admin'', ''sub_admin'', ''teacher'', ''assistant'')');
      updated_definition:=replace(updated_definition,
        '(''admin'',''teacher'',''assistant'')',
        '(''admin'',''sub_admin'',''teacher'',''assistant'')');
      updated_definition:=replace(updated_definition,
        '관리자·선생님·조교만 담당 조교를 배정할 수 있습니다.',
        '관리자·부관리자·선생님·조교만 담당 조교를 배정할 수 있습니다.');
    elsif target.proname='admin_update_account' then
      updated_definition:=replace(updated_definition,
        '(''teacher'',''assistant'',''manager'')',
        '(''teacher'',''sub_admin'',''assistant'',''manager'')');
      updated_definition:=replace(updated_definition,
        '(''teacher'', ''assistant'', ''manager'')',
        '(''teacher'', ''sub_admin'', ''assistant'', ''manager'')');
    elsif target.proname='admin_set_teacher_classes' then
      updated_definition:=replace(updated_definition,
        'p.role=''teacher''',
        'p.role in (''teacher'',''sub_admin'')');
      updated_definition:=replace(updated_definition,
        '교사 역할 계정을 선택해 주세요.',
        '교사 또는 부관리자 역할 계정을 선택해 주세요.');
    elsif target.proname='staff_class_lesson_history' then
      updated_definition:=replace(updated_definition,
        'v_role = ''teacher''',
        'v_role in (''teacher'',''sub_admin'')');
      updated_definition:=replace(updated_definition,
        'ct.teacher_profile_id = auth.uid()',
        'ct.profile_id = auth.uid()');
    elsif target.proname='delete_report_comment' then
      updated_definition:=replace(updated_definition,
        '(''teacher'',''manager'')',
        '(''teacher'',''sub_admin'',''manager'')');
      updated_definition:=replace(updated_definition,
        '(''teacher'', ''manager'')',
        '(''teacher'', ''sub_admin'', ''manager'')');
    elsif target.proname='admin_permanently_delete_class' then
      updated_definition:=replace(updated_definition,
        '(''teacher'', ''manager'')',
        '(''teacher'', ''sub_admin'', ''manager'')');
      updated_definition:=replace(updated_definition,
        '(''teacher'',''manager'')',
        '(''teacher'',''sub_admin'',''manager'')');
    end if;

    if updated_definition=original_definition then
      raise exception 'sub_admin permission alignment did not update function %',target.proname;
    end if;
    execute updated_definition;
  end loop;
end
$migration$;

-- Existing vice-director accounts must retain the staff directory row used by
-- class assignment and teacher pickers.
insert into public.teachers(profile_id,name)
select p.id,p.display_name
from public.profiles p
where p.role='sub_admin'
on conflict(profile_id) do update set name=excluded.name;

notify pgrst,'reload schema';
