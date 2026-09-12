import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
// PGLITE_MODULE may point to an isolated test dependency installation.
const {PGlite}=await import(process.env.PGLITE_MODULE||'@electric-sql/pglite');
const db=new PGlite();
await db.exec(await readFile(new URL('./database-fixture.sql',import.meta.url),'utf8'));
await db.exec(await readFile(new URL('../../supabase/migrations/20260911234033_class_record_conflict_protection.sql',import.meta.url),'utf8'));
const cid='00000000-0000-0000-0000-000000000002',a='00000000-0000-0000-0000-000000000011',b='00000000-0000-0000-0000-000000000012';
const change=(id,field,before,value)=>({path:['students',id,field],before,value});
const patch=async(changes,state='draft',mode='draft')=>(await db.query('select staff_patch_class_record($1,$2,$3,$4,$5) as s',[cid,'2026-09-11',JSON.stringify(changes),state,mode])).rows[0].s;
test('different students from the same baseline survive both saves',async()=>{await patch([change(a,'assignedHomework','','p10')]);const s=await patch([change(b,'assignedHomework','','p20')]);assert.equal(s.values.students[a].assignedHomework,'p10');assert.equal(s.values.students[b].assignedHomework,'p20');});
test('different fields on one student merge',async()=>{const s=await patch([change(a,'inspectionNote','','checked')]);assert.equal(s.values.students[a].assignedHomework,'p10');assert.equal(s.values.students[a].inspectionNote,'checked');});
test('same-field conflict rejects the entire save',async()=>{await assert.rejects(patch([{path:['notice'],before:'',value:'must roll back'},change(a,'assignedHomework','','stale')]),/다른 선생님/);const s=await patch([]);assert.equal(s.values.notice,'');assert.equal(s.values.students[a].assignedHomework,'p10');});
test('repeated identical save is idempotent',async()=>{const s=await patch([change(a,'assignedHomework','','p10')]);assert.equal(s.values.students[a].assignedHomework,'p10');});
test('invalid path is rejected',async()=>{await assert.rejects(patch([{path:['unexpected'],before:null,value:'x'}]),/지원하지/);});
test('state changes block stale draft saves',async()=>{await patch([],'draft','complete');await assert.rejects(patch([change(b,'assignedHomework','p20','stale')]),/완료 상태/);});
test('private revisions merge without publishing',async()=>{await patch([change(a,'assignedHomework','p10','private A')],'completed','revision');const s=await patch([change(b,'assignedHomework','p20','private B')],'completed','revision');assert.equal(s.values.students[a].assignedHomework,'private A');assert.equal(s.values.students[b].assignedHomework,'private B');const r=await db.query("select payload->'rows'->0->>'assignedHomework' as value from fixture_store");assert.equal(r.rows[0].value,'p10');});
test('publish preserves the other teacher private change',async()=>{const s=await patch([change(a,'inspectionNote','checked','published')],'completed','publish');assert.equal(s.revision,null);assert.equal(s.values.students[b].assignedHomework,'private B');});
test.after(async()=>db.close());
test('unauthorized teacher cannot read or write another class',async()=>{
 await db.exec("create or replace function current_user_role() returns text language sql as $$select 'teacher'::text$$");
 await assert.rejects(patch([],'completed','revision'),/담당 클래스/);
 await assert.rejects(db.query('select staff_class_edit_snapshot($1,$2)',[cid,'2026-09-11']),/담당 클래스/);
 await db.exec("create or replace function current_user_role() returns text language sql as $$select 'admin'::text$$");
});
test('RPC rolls back earlier writes when a later helper fails',async()=>{
 await db.exec("update lessons set status='draft'; create or replace function staff_save_class_lesson_content(uuid,date,p_content text) returns void language plpgsql as $$begin raise exception 'simulated downstream failure';end$$");
 await assert.rejects(patch([{path:['notice'],before:'',value:'not committed'},{path:['lessonContent'],before:'',value:'fail'}]),/simulated downstream/);
 const r=await db.query("select payload->>'notice' as value from fixture_store");assert.equal(r.rows[0].value,'');
});
