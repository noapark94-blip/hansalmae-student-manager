const {PGlite}=require('../family-database/node_modules/@electric-sql/pglite');
const fs=require('node:fs'),assert=require('node:assert/strict');
const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
(async()=>{const db=new PGlite();try{
await db.exec(fs.readFileSync('tests/class-participants/schema.sql','utf8'));
await db.exec(fs.readFileSync('supabase/migrations/20260924151450_class_day_participants.sql','utf8'));
const migration=fs.readdirSync('supabase/migrations').find(x=>x.endsWith('monthly_targets_from_regular_schedule.sql'));
await db.exec(fs.readFileSync('supabase/migrations/'+migration,'utf8'));
await db.exec(`set test.uid='${id(1)}';set test.role='admin';
insert into profiles(id,role,display_name) values('${id(1)}','admin','테스트');
insert into students(id,name,status) values('${id(2)}','교차수강','active'),('${id(3)}','고3 주2회','active'),('${id(4)}','수학 주3회','active');
insert into academy_subjects(id,name,main_subject) values('${id(10)}','영어','영어'),('${id(11)}','수학','수학');
insert into classes(id,name,subject,subject_id) values('${id(20)}','영어 A','영어','${id(10)}'),('${id(21)}','영어 B','영어','${id(10)}'),('${id(22)}','수학','수학','${id(11)}');
insert into enrollments(student_id,class_id,started_on) values('${id(2)}','${id(20)}','2019-01-01'),('${id(2)}','${id(21)}','2019-01-01'),('${id(3)}','${id(20)}','2019-01-01'),('${id(4)}','${id(22)}','2019-01-01');`);
for(const [sid,cid,day]of [[30,20,1],[31,20,3],[32,21,2],[33,21,4],[34,21,5],[35,22,1],[36,22,3],[37,22,5]])await db.query("insert into class_schedules(id,class_id,weekday,start_time,end_time,valid_from) values($1,$2,$3,'16:00','18:00','2019-01-01')",[id(sid),id(cid),day]);
for(const sid of [30,32,33])await db.query('insert into student_schedule_assignments(student_id,class_schedule_id) values($1,$2)',[id(2),id(sid)]);
const report=async()=>(await db.query("select staff_monthly_lesson_coverage('2020-01-01') r")).rows[0].r.items;
let rows=await report();const row=n=>rows.find(x=>x.studentId===id(n));assert.equal(row(2).target,12);assert.equal(row(2).weeklyCount,3);assert.equal(row(3).target,8);assert.equal(row(4).target,12);
// A historical row with the same recurring slot and a future replacement cannot inflate the target.
await db.exec(`insert into class_schedules(id,class_id,weekday,start_time,end_time,valid_from,valid_until) values('${id(38)}','${id(20)}',1,'16:00','18:00','2019-01-01','2019-12-31'),('${id(39)}','${id(20)}',5,'16:00','18:00','2020-02-01',null);insert into schedule_exceptions(class_id,original_date,kind) values('${id(20)}','2020-01-06','cancelled');`);
rows=await report();assert.equal(row(3).target,8);
// Makeup and extra sessions contribute once each; cancelled and absent sessions do not.
for(const [n,kind,status,attendance]of [[50,'makeup','completed','present'],[51,'extra','completed','late'],[52,'extra','cancelled','present'],[53,'makeup','completed','absent']]){
await db.query("insert into teacher_special_lessons(id,teacher_profile_id,subject_id,lesson_date,starts_at,ends_at,kind,status) values($1,$2,$3,'2020-01-10','18:00','20:00',$4,$5)",[id(n),id(1),id(10),kind,status]);await db.query('insert into teacher_special_lesson_students(session_id,student_id,attendance_status) values($1,$2,$3)',[id(n),id(3),attendance]);}
rows=await report();assert.equal(row(3).attended,2);assert.equal(row(3).target,8);assert.equal(row(3).absent,1);
await db.query("select admin_save_monthly_lesson_target($1,'수학','2020-01-01',10,null)",[id(4)]);rows=await report();assert.equal(row(4).target,10);assert.equal(row(4).targetOverridden,true);
await db.exec("set test.role='guardian'");await assert.rejects(report,/권한/);
console.log('PASS: cross-class assigned days, 2/3 weekly targets, math, historical/future schedules, cancellation, makeup/extra attendance, overrides, authorization.');
}finally{await db.close();}})().catch(e=>{console.error(e.message);process.exit(1)});
