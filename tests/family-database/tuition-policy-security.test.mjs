import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import assert from 'node:assert/strict';

test('tuition RLS isolates families, retains staff access and caches auth without changing writes', async () => {
  const db = new PGlite();
  const migration = readFileSync(new URL('../../supabase/migrations/20260928130737_harden_tuition_access_and_auth_policy_evaluation.sql', import.meta.url), 'utf8');
  try {
    await db.exec(`
      create role authenticated; create role anon; create schema auth;
      create function auth.uid() returns text language sql stable as $$ select current_setting('test.uid', true) $$;
      grant usage on schema auth to authenticated, anon;
      create function public.is_staff() returns boolean language sql stable as $$ select auth.uid() = 'staff' $$;
      create table students(id text primary key, profile_id text);
      create table guardians(id text primary key, profile_id text);
      create table student_guardians(student_id text, guardian_id text);
      create table tuition_charges(id text, student_id text);
      create table tuition_payments(id text);
      create table preferences(profile_id text, value text);
      create table message_logs(status text);
      create function normalize_message_approval_status() returns trigger language plpgsql as $$
      begin if new.status='queued' then new.status:='pending_approval'; end if; return new; end $$;
      create trigger normalize before insert on message_logs for each row execute function normalize_message_approval_status();
      grant select on students, guardians, student_guardians to authenticated;
      grant all on tuition_charges, tuition_payments, preferences to authenticated, anon;
      alter table tuition_charges enable row level security;
      alter table preferences enable row level security;
      create policy staff_manage_tuition_charges on tuition_charges for all to authenticated using(is_staff()) with check(is_staff());
      create policy family_read_tuition_charges on tuition_charges for select to authenticated using (
        exists(select 1 from students s where s.id=student_id and s.profile_id=auth.uid()) or
        exists(select 1 from student_guardians sg join guardians g on g.id=sg.guardian_id where sg.student_id=student_id and g.profile_id=auth.uid()));
      create policy own_preferences on preferences for all to authenticated using(profile_id=auth.uid()) with check(profile_id=auth.uid());
      insert into students values ('a','student-a'),('b','student-b');
      insert into guardians values ('ga','parent-a'),('gb','parent-b');
      insert into student_guardians values ('a','ga'),('b','gb');
      insert into tuition_charges values ('bill-a','a'),('bill-b','b');
    `);
    const bills = async user => {
      await db.query("select set_config('test.uid',$1,false)", [user]);
      await db.exec('set role authenticated');
      try { return (await db.query('select id from tuition_charges order by id')).rows.map(r=>r.id); }
      finally { await db.exec('reset role'); }
    };
    assert.deepEqual(await bills('parent-a'), ['bill-a','bill-b'], 'fixture reproduces original leak');
    await db.exec(migration);
    await db.exec(migration); // idempotency
    assert.deepEqual(await bills('parent-a'), ['bill-a']);
    assert.deepEqual(await bills('parent-b'), ['bill-b']);
    assert.deepEqual(await bills('student-a'), ['bill-a']);
    assert.deepEqual(await bills('unlinked'), []);
    assert.deepEqual(await bills('staff'), ['bill-a','bill-b']);
    await db.exec("set role anon");
    assert.deepEqual((await db.query('select * from tuition_charges')).rows, []);
    await db.exec('reset role');
    for (const role of ['anon','authenticated']) {
      for (const table of ['tuition_charges','tuition_payments']) {
        assert.equal((await db.query('select has_table_privilege($1,$2,\'TRUNCATE\') ok',[role,table])).rows[0].ok,false);
      }
    }
    await db.exec("select set_config('test.uid','parent-a',false); set role authenticated;");
    await db.exec("insert into preferences values ('parent-a','ok')");
    await assert.rejects(db.exec("insert into preferences values ('parent-b','forbidden')"), /row-level security/);
    await db.exec('reset role');
    await db.exec("insert into message_logs values ('queued'),('sent')");
    assert.deepEqual((await db.query('select status from message_logs order by status')).rows.map(r=>r.status),['pending_approval','sent']);
    const policy = (await db.query("select qual,with_check from pg_policies where policyname='own_preferences'")).rows[0];
    assert.match(policy.qual,/SELECT auth.uid/);
    assert.match(policy.with_check,/SELECT auth.uid/);
  } finally { await db.close(); }
});
