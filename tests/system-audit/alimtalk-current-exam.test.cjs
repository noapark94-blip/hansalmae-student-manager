// Isolated PostgreSQL regression: never connects to the production database.
const {PGlite}=require(process.env.HSM_PGLITE_MODULE||'@electric-sql/pglite');
const fs=require('node:fs'),assert=require('node:assert/strict');
(async()=>{const db=new PGlite();await db.exec(fs.readFileSync('tests/family-database/schema.sql','utf8'));
await db.exec(`create table correction_assignments(id uuid);create table if not exists class_makeup_attendees(class_id uuid,student_id uuid,attendance_date date);`);
await db.exec(fs.readFileSync('supabase/migrations/20260919092406_use_current_exam_in_alimtalk.sql','utf8'));
await db.exec(`insert into classes(id,name,subject) values(md5('class')::uuid,'가상 반','영어');
insert into lessons(id,class_id,lesson_date,starts_at,status) values(md5('lesson')::uuid,md5('class')::uuid,current_date,now(),'completed');
insert into attendance(id,lesson_id,student_id,status) values(md5('attendance')::uuid,md5('lesson')::uuid,md5('student')::uuid,'present');
insert into lesson_exam_results(id,lesson_id,student_id,exam_type,exam_title,score,max_score,evaluation,created_at,updated_at) values
(md5('current')::uuid,md5('lesson')::uuid,md5('student')::uuid,'영단어 시험','내신 단어 part2',80,100,'재시험',now()-interval '2 hours',now()),
(md5('obsolete')::uuid,md5('lesson')::uuid,md5('student')::uuid,'영단어 시험','내신단어 part2',null,100,'재시험',now()-interval '1 hour',now()-interval '1 hour');`);
const exams=async()=> (await db.query("select lessons->0->'exams' exams from internal_alimtalk_report_sources(array[md5('student')::uuid],current_date,current_date)")).rows[0].exams;
let e=await exams();assert.equal(e.length,1);assert.equal(e[0].score,80);assert.equal(e[0].examTitle,'내신 단어 part2');
await db.exec("update lesson_exam_results set score=null,evaluation='재시험 예정',updated_at=now() where id=md5('current')::uuid");e=await exams();assert.equal(e.length,1);assert.equal(e[0].score,null);assert.equal(e[0].evaluation,'재시험 예정');
await db.exec("update lesson_exam_results set exam_type='',exam_title='',evaluation='',feedback='' where id=md5('current')::uuid");assert.equal((await exams()).length,0,'cleared current exam must not revive historical values');
assert.equal((await db.query('select count(*)::int n from lesson_exam_results')).rows[0].n,2,'source selection never deletes original records');
console.log('PASS: only the editor current exam appears; edited null scores/feedback preserved; cleared exam does not revive stale duplicates; stored rows retained.');await db.close();})().catch(e=>{console.error(e.message);process.exit(1)});
