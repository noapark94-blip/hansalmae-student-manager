const {PGlite}=require(process.env.HSM_PGLITE_MODULE||'@electric-sql/pglite');const fs=require('node:fs'),assert=require('node:assert/strict');const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
(async()=>{const db=new PGlite();await db.exec(`create role anon;create role authenticated;create schema auth;create function auth.uid() returns uuid language sql as $$select nullif(current_setting('test.uid',true),'')::uuid$$;`);await db.exec(fs.readFileSync('tests/special-record/mixed-schema.sql','utf8'));
await db.exec(`alter table students add primary key(id);alter table teacher_special_lesson_students add column lesson_kind text,add column makeup_source text,add column makeup_source_id uuid;
create function current_user_role() returns public.user_role language sql set search_path=public as $$select coalesce(nullif(current_setting('test.role',true),''),'admin')::user_role$$;
create function is_staff() returns boolean language sql set search_path=public as $$select current_user_role() in ('admin','teacher','sub_admin','manager','assistant')$$;
create function internal_special_student_kind(uuid,uuid) returns text language sql as $$select coalesce(ss.lesson_kind,l.kind) from teacher_special_lesson_students ss join teacher_special_lessons l on l.id=ss.session_id where ss.session_id=$1 and ss.student_id=$2$$;
select set_config('test.uid','${id(1)}',false);
insert into students(id,name,status) values('${id(2)}','가상 학생','active'),('${id(3)}','다른 학생','active');
insert into academy_subjects(id,name,main_subject) values('${id(4)}','영어','영어'),('${id(40)}','국어','국어');
insert into classes(id,name,subject,subject_id,active) values('${id(5)}','가상 영어','영어','${id(4)}',true);
insert into class_teachers values('${id(5)}','${id(1)}');
insert into enrollments(student_id,class_id,status,started_on) values('${id(2)}','${id(5)}','active','2019-01-01');
insert into class_schedules(id,class_id,weekday,start_time,end_time,valid_from) values('${id(6)}','${id(5)}',1,'16:00','17:30','2090-01-01'),('${id(7)}','${id(5)}',3,'16:00','17:30','2090-01-01');
insert into student_schedule_assignments values('${id(2)}','${id(6)}');
`);
const old=fs.readFileSync('tests/schedule-swap/existing-functions.sql','utf8');await db.exec(old.slice(old.indexOf('CREATE OR REPLACE FUNCTION public.student_uses_class_schedule')));
const helper=fs.readFileSync('supabase/migrations/20260919102036_audit_class_schedule_record_consistency.sql','utf8');await db.exec(helper.slice(0,helper.indexOf('CREATE OR REPLACE FUNCTION public.family_learning_calendar_schedule')));
await db.exec(fs.readFileSync('supabase/migrations/20260919112542_monthly_lesson_coverage.sql','utf8'));
await db.exec(fs.readFileSync('supabase/migrations/20260919115104_monthly_coverage_ended_enrollments.sql','utf8'));
const report=async month=>(await db.query('select staff_monthly_lesson_coverage($1) r',[month])).rows[0].r;
const future=await report('2090-01-01');let r=future.items[0];const mondays=(await db.query("select count(*)::int n from generate_series(date '2090-01-01',date '2090-01-31',interval '1 day') d where extract(isodow from d)=1")).rows[0].n;assert.equal(r.planned,mondays);assert.equal(r.attended,0);assert.equal(r.target,12);
await db.exec(`insert into lessons(id,class_id,lesson_date,starts_at,ends_at,status) values
('${id(10)}','${id(5)}','2020-01-06','2020-01-06 16:00+09','2020-01-06 17:30+09','completed'),
('${id(11)}','${id(5)}','2020-01-06','2020-01-06 18:00+09','2020-01-06 19:30+09','draft'),
('${id(12)}','${id(5)}','2020-01-07','2020-01-07 16:00+09','2020-01-07 17:30+09','completed'),
('${id(13)}','${id(5)}','2020-01-08','2020-01-08 16:00+09','2020-01-08 17:30+09','completed'),
('${id(14)}','${id(5)}','2019-12-08','2019-12-08 16:00+09','2019-12-08 17:30+09','completed');
insert into attendance(id,lesson_id,student_id,status) values('${id(20)}','${id(10)}','${id(2)}','present'),('${id(21)}','${id(12)}','${id(2)}','late'),('${id(22)}','${id(13)}','${id(2)}','absent'),('${id(23)}','${id(14)}','${id(2)}','absent');
insert into teacher_special_lessons(id,teacher_profile_id,lesson_date,starts_at,ends_at,kind,subject_id,status) values
('${id(30)}','${id(1)}','2020-01-09','16:00','17:30','makeup','${id(4)}','completed'),
('${id(31)}','${id(1)}','2020-01-10','16:00','17:30','extra','${id(4)}','completed'),
('${id(32)}','${id(1)}','2020-01-13','16:00','17:30','extra','${id(4)}','cancelled'),
('${id(33)}','${id(1)}','2020-01-14','16:00','17:30','extra','${id(4)}','draft');
insert into teacher_special_lesson_students(session_id,student_id,attendance_status,makeup_source,makeup_source_id) values
('${id(30)}','${id(2)}','present','regular','${id(22)}'),('${id(31)}','${id(2)}','late',null,null),('${id(32)}','${id(2)}','present',null,null),('${id(33)}','${id(2)}',null,null,null);
insert into makeup_sessions(id,attendance_id,scheduled_at,ends_at,status) values('${id(50)}','${id(22)}','2020-01-09 16:00+09','2020-01-09 17:30+09','completed'),('${id(51)}','${id(23)}','2020-01-12 16:00+09','2020-01-12 17:30+09','completed');
insert into correction_reports(id,student_id,correction_date,subject,attendance_status) values('${id(60)}','${id(2)}','2020-01-11','영어','present');`);
r=(await report('2020-01-01')).items[0];assert.equal(r.attended,5);assert.equal(r.absent,1);assert.equal(r.unrecorded,1);assert.equal(r.planned,0);assert.equal(r.events.filter(e=>e.id.startsWith('regular:')&&e.date==='2020-01-06').length,1);
await db.query('select admin_save_monthly_lesson_target($1,$2,$3,$4,$5)',[id(2),'영어','2020-01-01',5,null]);r=(await report('2020-01-01')).items[0];assert.equal(r.target,5);assert.equal(r.version,1);await assert.rejects(db.query('select admin_save_monthly_lesson_target($1,$2,$3,$4,$5)',[id(2),'영어','2020-01-01',6,null]),/변경/);assert.equal((await report('2090-01-01')).items[0].target,12);
// Cancel one selected day; move another day; duplicate makeup/roster sources still yield one event.
const dates=(await db.query("select d::date::text d from generate_series(date '2090-01-01',date '2090-01-31',interval '1 day') d where extract(isodow from d)=1 order by d")).rows.map(x=>x.d);
await db.query("insert into schedule_exceptions(id,class_id,original_date,kind) values($1,$2,$3,'cancelled')",[id(70),id(5),dates[0]]);
await db.query("insert into schedule_exceptions(id,class_id,original_date,replacement_date,kind,start_time,end_time) values($1,$2,$3,$3::date+1,'changed','17:00','18:30')",[id(71),id(5),dates[1]]);
await db.query('insert into class_makeup_attendees(class_id,student_id,attendance_date) values($1,$2,$3)',[id(5),id(2),dates[2]]);
r=(await report('2090-01-01')).items[0];assert.equal(r.planned,mondays-1);assert.ok(r.events.some(e=>e.time==='17:00'));
// Class makeup-only students are visible without an enrollment; Korean defaults to eight.
await db.exec(`insert into classes(id,name,subject,subject_id,active) values('${id(80)}','가상 국어','국어','${id(40)}',true);
insert into class_schedules(id,class_id,weekday,start_time,end_time,valid_from) values('${id(81)}','${id(80)}',1,'16:00','17:30','2090-01-01');
insert into class_makeup_attendees(class_id,student_id,attendance_date) values('${id(80)}','${id(3)}','2090-01-03');`);
const korean=(await report('2090-01-01')).items.find(x=>x.studentId===id(3));assert.equal(korean.target,8);assert.equal(korean.planned,1);
// Ended enrollment retains history without flagging a full-month target.
await db.exec(`update enrollments set status='completed',ended_on='2020-01-10' where student_id='${id(2)}'`);
r=(await report('2020-01-01')).items.find(x=>x.studentId===id(2));assert.equal(r.enrollmentEnded,true);assert.equal(r.attended,5);assert.ok(r.events.length);
assert.equal((await report('2019-12-01')).items.find(x=>x.studentId===id(2)).enrollmentEnded,false);
assert.equal(korean.enrollmentEnded,false);
// Same-subject transfer remains eligible even when the old class ended.
await db.exec(`insert into classes(id,name,subject,subject_id,active) values('${id(90)}','새 영어','영어','${id(4)}',true);
insert into enrollments(student_id,class_id,status,started_on) values('${id(2)}','${id(90)}','active','2020-01-11');`);
assert.equal((await report('2020-01-01')).items.find(x=>x.studentId===id(2)).enrollmentEnded,false);
await db.exec(`select set_config('test.role','teacher',false),set_config('test.uid','${id(99)}',false)`);assert.equal((await report('2020-01-01')).items.length,0);await assert.rejects(db.query('select admin_save_monthly_lesson_target($1,$2,$3,$4,$5)',[id(2),'영어','2020-01-01',6,1]),/관리자/);
await db.exec(`select set_config('test.role','guardian',false)`);await assert.rejects(report('2020-01-01'),/권한/);await db.exec(`select set_config('test.role','admin',false),set_config('test.uid','',false)`);await assert.rejects(report('2020-01-01'),/권한/);
assert.equal((await db.query("select has_function_privilege('anon','staff_monthly_lesson_coverage(date)','execute') allowed")).rows[0].allowed,false);
console.log('PASS: selected schedules, monthly boundaries, present/late, correction exclusion, linked makeup dedup, cancelled/missing attendance, date changes, target versioning and authorization.');await db.close();})().catch(e=>{console.error(e);process.exit(1)});
