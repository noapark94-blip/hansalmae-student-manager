const {PGlite}=require(process.env.HSM_PGLITE_MODULE||'@electric-sql/pglite');
const fs=require('node:fs'),assert=require('node:assert/strict');const id=n=>`00000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
(async()=>{const db=new PGlite();await db.exec(`create role anon;create role authenticated;create schema auth;create function auth.uid() returns uuid language sql as $$select '${id(1)}'::uuid$$;`);
await db.exec(fs.readFileSync('tests/special-record/mixed-schema.sql','utf8'));
await db.exec(`create function is_staff() returns boolean language sql as $$select true$$;
create function current_user_role() returns user_role language sql as $$select coalesce(nullif(current_setting('test.role',true),''),'admin')::user_role$$;
create function internal_family_student_id(uuid) returns uuid language sql as $$select $1$$;
create function family_student_context(uuid) returns jsonb language sql as $$select '{}'::jsonb$$;
create function family_live_dashboard(uuid) returns jsonb language sql as $$select jsonb_build_object('selectedStudent',jsonb_build_object('id',$1))$$;
create function internal_special_student_kind(uuid,uuid) returns text language sql as $$select 'makeup'::text$$;
create function correction_time_start(time,smallint) returns time language sql as $$select $1$$;
create function correction_time_end(time,smallint) returns time language sql as $$select $1$$;
insert into profiles(id,display_name,role,is_active) values('${id(1)}','가상 선생님','admin',true);
insert into students(id,name,status) values('${id(2)}','가상 학생','active'),('${id(3)}','가상 다른학생','active');
insert into classes(id,name,room,active,subject) values('${id(4)}','가상 영어','101',true,'영어'),('${id(5)}','가상 수학','102',true,'수학');
insert into class_teachers(class_id,profile_id) values('${id(4)}','${id(1)}');
insert into class_schedules(id,class_id,weekday,start_time,end_time) values('${id(6)}','${id(4)}',extract(isodow from current_date),'14:00','15:30');
insert into enrollments(id,class_id,student_id,status,started_on) values('${id(7)}','${id(4)}','${id(2)}','active',current_date-20);
insert into student_schedule_assignments(student_id,class_schedule_id) values('${id(2)}','${id(6)}');
insert into lessons(id,class_id,lesson_date,starts_at,ends_at,status,lesson_content) values('${id(8)}','${id(4)}',current_date,(current_date+time '11:00') at time zone 'Asia/Seoul',(current_date+time '12:30') at time zone 'Asia/Seoul','completed','보존할 수업');
insert into attendance(id,lesson_id,student_id,status) values('${id(9)}','${id(8)}','${id(2)}','present');
insert into lessons(id,class_id,lesson_date,starts_at,ends_at,status) values('${id(10)}','${id(4)}',current_date,(current_date+time '14:00') at time zone 'Asia/Seoul',(current_date+time '15:30') at time zone 'Asia/Seoul','draft');`);
await db.exec(fs.readFileSync('tests/schedule-swap/audit-existing-functions.sql','utf8'));
const calendar=async(student=id(2),date=null)=>(await db.query('select family_learning_calendar_schedule($1,coalesce($2::date,current_date)) r',[student,date])).rows[0].r;
const today=(await db.query('select current_date::text d')).rows[0].d;
assert.equal((await calendar()).find(r=>r.date===today).startTime,'14:00'); // Reproduced stale historical time.
assert.equal((await db.query('select family_today_lessons($1) r',[id(2)])).rows[0].r.length,2); // Empty draft duplicates saved lesson.
await db.exec(`delete from student_schedule_assignments;update enrollments set status='completed',ended_on=current_date;`);
assert.equal((await db.query('select staff_class_day($1,current_date) r',[id(4)])).rows[0].r.students.length,0); // Saved student disappears after removal.
await db.exec(fs.readFileSync('supabase/migrations/20260919102036_audit_class_schedule_record_consistency.sql','utf8'));
const reads=(await db.query('select staff_class_family_report_read_status($1,current_date) r',[id(4)])).rows[0].r;assert.equal(reads.totalStudents,1);
let c=await calendar();assert.equal(c.filter(r=>r.date===today).length,1);assert.equal(c.find(r=>r.date===today).startTime,'11:00');assert.equal(c.find(r=>r.date===today).attendanceStatus,'present');
assert.equal((await db.query('select staff_class_day($1,current_date) r',[id(4)])).rows[0].r.students[0].name,'가상 학생');
assert.equal((await db.query('select family_today_lessons($1) r',[id(2)])).rows[0].r.length,1);
// A weekday move must not remove an already saved lesson from the teacher agenda.
await db.exec(`update class_schedules set weekday=case when weekday=7 then 1 else weekday+1 end where id='${id(6)}'`);
assert.equal((await db.query('select staff_class_agenda(current_date) r')).rows[0].r.filter(r=>r.classId===id(4)).length,1);
await db.exec(`update class_schedules set weekday=extract(isodow from current_date) where id='${id(6)}'`);
// Historical duplicate attendance is displayed once, without deleting either row.
await db.exec(`insert into attendance(id,lesson_id,student_id,status) values('${id(11)}','${id(10)}','${id(2)}','absent')`);
let ac=(await db.query("select staff_class_attendance_calendar($1,current_date,'week') r",[id(4)])).rows[0].r;assert.equal(ac.find(r=>r.date===today).students.length,1);assert.equal(ac.find(r=>r.date===today).students[0].status,'present');
await db.exec(`insert into enrollments(id,class_id,student_id,status,started_on) values('${id(12)}','${id(4)}','${id(3)}','active',current_date+1);insert into student_schedule_assignments(student_id,class_schedule_id) values('${id(3)}','${id(6)}');`);
assert.equal((await db.query('select student_attends_class_on($1,$2,current_date) r',[id(3),id(4)])).rows[0].r,false);
// An exception on an unselected weekday must not create a phantom family lesson.
await db.exec(`update enrollments set started_on=current_date-20 where student_id='${id(3)}';insert into schedule_exceptions(id,class_id,original_date,replacement_date,kind,start_time,end_time) values('${id(13)}','${id(4)}',current_date-1,current_date+1,'changed','17:00','18:30');`);
assert.equal((await calendar(id(3))).some(r=>r.id==='regular-change:'+id(13)),false);
// Saving a moved lesson on a new weekday uses the replacement time and one stable ID.
await db.exec(`alter table lessons add unique(class_id,starts_at);alter table lessons alter column id set default gen_random_uuid();alter table lessons alter column status set default 'draft';
update schedule_exceptions set original_date=current_date where id='${id(13)}';`);
const moved=(await db.query('select staff_save_class_day($1,current_date+1,null,null,null) id',[id(4)])).rows[0].id;
assert.equal((await db.query('select staff_save_class_day($1,current_date+1,null,null,null) id',[id(4)])).rows[0].id,moved);
assert.equal((await db.query("select to_char(starts_at at time zone 'Asia/Seoul','HH24:MI') t from lessons where id=$1",[moved])).rows[0].t,'17:00');
assert.equal((await db.query('select student_attends_class_on($1,$2,current_date+1) r',[id(3),id(4)])).rows[0].r,true);
// Expired room/teacher schedules should not block a current time edit; current conflicts identify the other class.
await db.exec(`create trigger audit_conflict after insert or update on class_schedules for each row execute function prevent_class_schedule_conflict();
insert into class_schedules(id,class_id,weekday,start_time,end_time,valid_until) values('${id(14)}','${id(5)}',extract(isodow from current_date),'14:00','15:30',current_date-1);
update classes set room='101' where id='${id(5)}';insert into class_teachers values('${id(5)}','${id(1)}');update class_schedules set start_time='14:00' where id='${id(6)}';`);
await assert.rejects(db.exec(`update class_schedules set valid_until=null where id='${id(14)}'`),/가상 선생님.*가상 영어.*14:00–15:30/);
await db.exec(`delete from class_teachers where class_id='${id(5)}'`);
await assert.rejects(db.exec(`update class_schedules set valid_until=null where id='${id(14)}'`),/강의실.*101.*가상 영어/);
await db.exec(`update classes set room='102' where id='${id(5)}';update class_schedules set valid_until=null,start_time='15:30',end_time='17:00' where id='${id(14)}'`); // Touching endpoint allowed.
assert.equal((await db.query('select count(*)::int n from lessons')).rows[0].n,3);assert.equal((await db.query('select count(*)::int n from attendance')).rows[0].n,2);
// The shared conflict trigger must still support an atomic two-class swap.
await db.exec(fs.readFileSync('supabase/migrations/20260919160338_swap_class_schedule_times.sql','utf8'));
// Empty unrelated hub tables: only class schedule metadata is exercised here.
await db.exec(`create table correction_exceptions(id uuid,assignment_id uuid,week_start date,weekday smallint,slot_index smallint,note text);
create table correction_slot_capacities(teacher_profile_id uuid,weekday smallint,slot_index smallint,capacity integer);
create table vehicle_runs(id uuid,manager_profile_id uuid,weekday smallint,pickup_time time,pickup_location text,active boolean);
create table vehicle_boardings(run_id uuid,student_id uuid);`);
await db.exec(fs.readFileSync('supabase/migrations/20260919104128_align_swap_validity_checks.sql','utf8'));
const hubRows=(await db.query('select staff_schedule_hub() r')).rows[0].r.classSchedules;assert.equal(hubRows[0].active,true);assert.ok(Object.hasOwn(hubRows[0],'validUntil'));
const base=async sid=>(await db.query("select jsonb_build_object('weekday',weekday,'startTime',to_char(start_time,'HH24:MI'),'endTime',to_char(end_time,'HH24:MI'),'teacherIds',coalesce((select jsonb_agg(profile_id::text order by profile_id) from class_teachers where class_id=s.class_id),'[]'::jsonb)) b from class_schedules s where id=$1",[sid])).rows[0].b;
const firstBase=await base(id(6)),secondBase=await base(id(14));
await db.query('select staff_swap_class_schedule_times($1,$2,$3,$4)',[id(6),id(14),JSON.stringify(firstBase),JSON.stringify(secondBase)]);
assert.equal((await base(id(6))).startTime,'15:30');assert.equal((await base(id(14))).startTime,'14:00');
assert.equal((await db.query('select count(*)::int n from student_schedule_assignments')).rows[0].n,1);
// Expired same-class rows must not block a swap; expired source rows must reject atomically.
await db.exec(`insert into class_schedules(id,class_id,weekday,start_time,end_time,valid_until) values('${id(30)}','${id(4)}',extract(isodow from current_date),'14:00','15:30',current_date-1)`);
const swapAgain=async()=>db.query('select staff_swap_class_schedule_times($1,$2,$3,$4)',[id(6),id(14),JSON.stringify(await base(id(6))),JSON.stringify(await base(id(14)))]);
await swapAgain();assert.equal((await base(id(6))).startTime,'14:00');
const beforeExpired=await base(id(6));
await assert.rejects(db.query('select staff_swap_class_schedule_times($1,$2,$3,$4)',[id(6),id(30),JSON.stringify(beforeExpired),JSON.stringify(await base(id(30)))]),/종료된/);
assert.deepEqual(await base(id(6)),beforeExpired);
await db.exec(`delete from class_schedules where id='${id(30)}'`);
// The family report and graph must use the same current exam as the editor/alimtalk.
await db.exec(`update students set profile_id='${id(1)}' where id='${id(2)}';
insert into lesson_exam_results(id,lesson_id,student_id,exam_type,exam_title,score,max_score,evaluation,created_at) values
('${id(20)}','${id(8)}','${id(2)}','영단어','현재 시험',96,100,'현재 피드백',now()-interval '2 hours'),
('${id(21)}','${id(8)}','${id(2)}','영단어','중복 시험',80,100,'오래된 피드백',now()-interval '1 hour'),
('${id(22)}','${id(10)}','${id(2)}','영단어','임시 시험',70,100,'미완료',now());
select set_config('test.role','student',false);`);
const summary=async()=>(await db.query('select family_summary_snapshot($1,current_date,current_date) r',[id(2)])).rows[0].r.lessons;
let report=await summary();assert.equal(report.length,1);assert.equal(report[0].exams.length,1);assert.equal(report[0].exams[0].score,96);
let graph=(await db.query('select family_exam_progress($1) r',[id(2)])).rows[0].r;assert.equal(graph.length,1);assert.equal(graph[0].score,96);
assert.equal((await db.query('select family_completed_learning_reports($1,20) r',[id(2)])).rows[0].r[0].exams.length,1);
await db.exec(`update lesson_exam_results set score=null,exam_type='',exam_title='',evaluation='',feedback='' where id='${id(20)}'`);
assert.equal((await summary())[0].exams.length,0);assert.equal((await db.query('select family_exam_progress($1) r',[id(2)])).rows[0].r.length,0);
assert.equal((await db.query('select count(*)::int n from lesson_exam_results')).rows[0].n,3);
console.log('PASS: atomic swap and current family exam selection; reproduced and fixed lost historical roster, changed historical time and duplicate today rows; validity/exception filters, duplicate attendance, named teacher/room conflicts, expired schedules and touching endpoints; all saved rows retained.');await db.close();})().catch(e=>{console.error(e);process.exit(1)});
