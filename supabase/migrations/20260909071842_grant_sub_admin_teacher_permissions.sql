-- A sub administrator is a vice-director: the teacher role plus messaging tools.
create or replace function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select role in ('admin','sub_admin','teacher','assistant','manager') and is_active
    from public.profiles
    where id = auth.uid()
  ), false)
$$;

create or replace function public.can_staff_report_student(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_user_role()='admin' or (
    public.current_user_role() in ('teacher','sub_admin') and (
      exists(select 1 from public.enrollments e join public.class_teachers ct on ct.class_id=e.class_id where e.student_id=p_student_id and ct.profile_id=auth.uid())
      or exists(select 1 from public.teacher_special_lesson_students a join public.teacher_special_lessons l on l.id=a.session_id where a.student_id=p_student_id and l.teacher_profile_id=auth.uid())
      or exists(select 1 from public.correction_assignments ca where ca.student_id=p_student_id and ca.teacher_profile_id=auth.uid())
    )
  )
$$;

create or replace function public.staff_class_teacher_options()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case when public.is_staff() then coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.display_name) order by p.display_name),'[]'::jsonb) else '[]'::jsonb end
  from public.profiles p
  where p.role in ('admin','teacher','sub_admin')
    and p.is_active
    and (public.current_user_role()='admin' or p.id=auth.uid())
$$;

-- Keep every existing teacher-capable RPC aligned with the vice-director role.
do $migration$
declare
  target record;
  original_definition text;
  updated_definition text;
begin
  for target in
    select p.oid, pg_get_functiondef(p.oid) as definition
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prokind='f'
  loop
    original_definition := target.definition;
    updated_definition := original_definition;
    updated_definition := replace(updated_definition, '(''admin'',''teacher'')', '(''admin'',''teacher'',''sub_admin'')');
    updated_definition := replace(updated_definition, '(''admin'', ''teacher'')', '(''admin'', ''teacher'', ''sub_admin'')');
    updated_definition := replace(updated_definition, '(''admin'',''teacher'',''manager'')', '(''admin'',''teacher'',''sub_admin'',''manager'')');
    updated_definition := replace(updated_definition, '(''admin'', ''teacher'', ''manager'')', '(''admin'', ''teacher'', ''sub_admin'', ''manager'')');
    updated_definition := replace(updated_definition, '(''admin'',''teacher'',''assistant'',''manager'')', '(''admin'',''teacher'',''sub_admin'',''assistant'',''manager'')');
    updated_definition := replace(updated_definition, '(''admin'', ''teacher'', ''assistant'', ''manager'')', '(''admin'', ''teacher'', ''sub_admin'', ''assistant'', ''manager'')');
    if updated_definition <> original_definition then execute updated_definition; end if;
  end loop;
end
$migration$;

alter policy "eligible profiles manage own push subscriptions"
on public.push_subscriptions
using (
  profile_id=(select auth.uid()) and exists(
    select 1 from public.profiles p
    where p.id=(select auth.uid())
      and p.role in ('guardian','teacher','sub_admin','assistant','admin','manager')
  )
)
with check (
  profile_id=(select auth.uid()) and exists(
    select 1 from public.profiles p
    where p.id=(select auth.uid())
      and p.role in ('guardian','teacher','sub_admin','assistant','admin','manager')
  )
);

alter policy source_makeup_sessions_staff
on public.source_makeup_sessions
using (public.current_user_role() in ('admin','teacher','sub_admin','manager'))
with check (public.current_user_role() in ('admin','teacher','sub_admin','manager'));

alter policy student_academic_records_staff_select
on public.student_academic_records
using (public.current_user_role() in ('admin','teacher','sub_admin','manager'));

alter policy student_academic_records_staff_insert
on public.student_academic_records
with check (public.current_user_role() in ('admin','teacher','sub_admin','manager') and created_by=(select auth.uid()));

alter policy student_academic_records_staff_update
on public.student_academic_records
using (public.current_user_role() in ('admin','teacher','sub_admin','manager'))
with check (public.current_user_role() in ('admin','teacher','sub_admin','manager'));

alter policy student_academic_records_staff_delete
on public.student_academic_records
using (public.current_user_role() in ('admin','teacher','sub_admin','manager'));

alter policy "Staff can read vocabulary sets"
on public.vocabulary_word_sets
using ((select public.current_user_role()) in ('admin','teacher','sub_admin','assistant','manager'));

alter policy "Staff can read vocabulary words"
on public.vocabulary_words
using ((select public.current_user_role()) in ('admin','teacher','sub_admin','assistant','manager'));

alter policy "Staff can read vocabulary history"
on public.vocabulary_test_history
using ((select public.current_user_role()) in ('admin','teacher','sub_admin','assistant','manager'));

alter policy "Staff can create vocabulary history"
on public.vocabulary_test_history
with check (created_by=(select auth.uid()) and (select public.current_user_role()) in ('admin','teacher','sub_admin','assistant','manager'));
