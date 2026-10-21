import {PGlite} from '../family-database/node_modules/@electric-sql/pglite/dist/index.js';
import fs from 'node:fs';import assert from 'node:assert/strict';
const db=new PGlite();const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
await db.exec(`create role anon;create role authenticated;create schema auth;create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;create function public.is_staff() returns boolean language sql as $$select coalesce(current_setting('test.staff',true),'')='yes'$$;create table fixture(rows jsonb);create function tuition_board(date) returns jsonb language sql as $$select jsonb_build_object('items',rows) from fixture$$;create table message_logs(id uuid default gen_random_uuid(),student_id uuid,recipient_name text,recipient_phone text,message_type text,body text,provider text,status text,queue_batch_id uuid,created_at timestamptz default now(),sent_at timestamptz);`);
await db.exec(fs.readFileSync('supabase/migrations/20261021063813_tuition_selected_messages.sql','utf8'));
const rows=[1,2,3].map(n=>({id:id(n),studentId:id(n+10),studentName:`테스트${n}`,grade:'중3',school:'테스트중',status:'open',totalAmount:270000,paidAmount:0,balance:270000,guardianPhones:n===3?['없음']:['010-0000-0000']}));await db.query('insert into fixture values($1)',[JSON.stringify(rows)]);
const template='{학생명} {월} 납부 {납부액}원 잔여 {미납액}원';const ids=rows.map(r=>r.id);
await assert.rejects(db.query('select staff_preview_tuition_messages($1,$2,$3)',['2026-10-01',ids,template]),/교직원/);
await db.exec(`select set_config('test.uid','${id(99)}',false);select set_config('test.staff','yes',false)`);
async function preview(){return (await db.query('select staff_preview_tuition_messages($1,$2,$3) as p',['2026-10-01',ids,template])).rows[0].p}
const p=await preview();assert.equal(p.recipients.length,1);assert.equal(p.recipients[0].students.length,2);assert.match(p.recipients[0].body,/2026년 10월/);assert.match(p.recipients[0].body,/270,000/);assert.equal(p.snapshot.length,3);
const args=['2026-10-01',ids,template,JSON.stringify(p),id(90)];const queue=()=>db.query('select staff_queue_tuition_messages($1,$2,$3,$4,$5) as n',args);
assert.equal((await queue()).rows[0].n,1);assert.equal((await queue()).rows[0].n,1);assert.equal((await db.query('select count(*)::int n from message_logs')).rows[0].n,1);
rows[0].status='paid';rows[0].paidAmount=270000;rows[0].balance=0;await db.query('update fixture set rows=$1',[JSON.stringify(rows)]);
await assert.rejects(db.exec("update message_logs set status='sending'"),/변경/);
await assert.rejects(db.query('select staff_queue_tuition_messages($1,$2,$3,$4,$5)',['2026-10-01',ids,template,JSON.stringify(p),id(91)]),/변경/);
assert.equal((await db.query('select status from message_logs')).rows[0].status,'pending_approval');
const fresh=await preview();await db.query('select staff_queue_tuition_messages($1,$2,$3,$4,$5)',['2026-10-01',ids,template,JSON.stringify(fresh),id(92)]);await db.query("update message_logs set status='sending' where queue_batch_id=$1",[id(92)]);assert.equal((await db.query("select count(*)::int n from message_logs where status='sending'")).rows[0].n,1);
console.log('PASS authorization, month/template, sibling merge, invalid phones, idempotency, stale queue and delivery blocking');await db.close();
