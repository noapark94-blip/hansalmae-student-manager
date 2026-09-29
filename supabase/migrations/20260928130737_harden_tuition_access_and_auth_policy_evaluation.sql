-- Keep the outer billing row explicit: an unqualified student_id inside the
-- guardian subquery binds to sg.student_id and accidentally becomes a tautology.
set lock_timeout = '5s';
alter policy family_read_tuition_charges on public.tuition_charges using (
  exists (select 1 from public.students s
    where s.id = tuition_charges.student_id and s.profile_id = (select auth.uid()))
  or exists (select 1 from public.student_guardians sg
    join public.guardians g on g.id = sg.guardian_id
    where sg.student_id = tuition_charges.student_id and g.profile_id = (select auth.uid()))
);

-- RLS does not protect TRUNCATE. Client roles only need ordinary row operations.
revoke truncate, references, trigger on public.tuition_charges, public.tuition_payments from anon, authenticated;

-- This trigger only changes NEW.status and needs no application search path.
alter function public.normalize_message_approval_status() set search_path = '';

-- auth.uid() is constant for a statement. An uncorrelated scalar subquery lets
-- PostgreSQL evaluate it once, preserving all roles, predicates and commands.
-- Policies already using an initplan are deliberately left alone; reruns are safe.
do $migration$
declare p record; q text; c text; ddl text;
begin
  for p in select * from pg_policies where schemaname = 'public'
    and (coalesce(qual, '') || coalesce(with_check, '')) like '%auth.uid()%'
    and (coalesce(qual, '') || coalesce(with_check, '')) not like '%SELECT auth.uid()%'
  loop
    q := replace(p.qual, 'auth.uid()', '(SELECT auth.uid())');
    c := replace(p.with_check, 'auth.uid()', '(SELECT auth.uid())');
    ddl := format('ALTER POLICY %I ON %I.%I', p.policyname, p.schemaname, p.tablename);
    if q is not null then ddl := ddl || format(' USING (%s)', q); end if;
    if c is not null then ddl := ddl || format(' WITH CHECK (%s)', c); end if;
    execute ddl;
  end loop;
end
$migration$;
reset lock_timeout;
