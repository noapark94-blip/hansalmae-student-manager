// Runs ONLY in a new, in-memory PGlite database; no remote connection is accepted.
import { PGlite } from '@electric-sql/pglite';
import { readFileSync } from 'node:fs';
import { before, beforeEach, after, test } from 'node:test';
import assert from 'node:assert/strict';
const db = new PGlite();
const read = name => readFileSync(new URL(name, import.meta.url), 'utf8');
const id = n => `00000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const A=id(1),B=id(2),P=id(11),OTHER=id(12),C=id(21),G=id(31);
let today;
before(async()=>{
 await db.exec(`create role anon; create role authenticated; create schema auth;
 create type public.user_role as enum ('student','guardian','teacher','admin');
 create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid',true),'')::uuid $$;
 create function public.current_user_role() returns public.user_role language sql stable as $$ select nullif(current_setting('test.role',true),'')::public.user_role $$;`);
 await db.exec(read('schema.sql'));
 await db.exec(read('original-report-functions.sql'));
 await db.exec(read('../../supabase/migrations/20260913103003_family_page_queries_and_period_summary.sql'));
 await db.exec(read('../../supabase/migrations/20260913123906_family_previous_homework_lookup.sql'));
 today=(await db.query('select current_date::text today')).rows[0].today;
});
beforeEach(async()=>{
 await db.exec(`truncate students,guardians,student_guardians,classes,class_schedules,class_teachers,profiles,enrollments,student_schedule_assignments,lessons,attendance,lesson_homework_results,class_daily_notices,lesson_exam_results,teacher_special_lessons,teacher_special_lesson_students,teacher_special_lesson_exam_results,academy_subjects,correction_reports;
 select set_config('test.uid','${P}',false),set_config('test.role','guardian',false);
 insert into students(id,profile_id,name,school,grade) values ('${A}','${id(41)}','Test A','Test school','고1'),('${B}','${id(42)}','Test B','Test school','고2');
 insert into guardians(id,profile_id) values ('${G}','${P}'),('${id(32)}','${OTHER}');
 insert into student_guardians(student_id,guardian_id,is_primary) values ('${A}','${G}',true),('${B}','${id(32)}',true);
 insert into classes(id,name,subject,active,color) values ('${C}','Test class','수학',true,'#123456');`);
});
after(()=>db.close());
const snapshot = async (student=A,start=today,end=today) => (await db.query('select family_summary_snapshot($1,$2,$3) data',[student,start,end])).rows[0].data;
const context = async (student=A,include=false) => (await db.query('select family_student_context($1,$2) data',[student,include])).rows[0].data;
async function regular(n=1,student=A,date='current_date',status='completed'){
 await db.exec(`insert into lessons(id,class_id,lesson_date,starts_at,status,lesson_content,homework_content)
 select md5('lesson'||g)::uuid,'${C}',${date},(${date})::timestamp + interval '12 hours' + g*interval '1 minute','${status}','공통 내용','공통 숙제' from generate_series(1,${n})g;
 insert into attendance(id,lesson_id,student_id,status) select md5('attendance'||g)::uuid,md5('lesson'||g)::uuid,'${student}','present' from generate_series(1,${n})g;`);
}
async function special(){await db.exec(`insert into teacher_special_lessons(id,lesson_date,starts_at,kind,status) values ('${id(101)}',current_date,'15:00','extra','completed'),('${id(102)}',current_date,'16:00','makeup','completed');
 insert into teacher_special_lesson_students(session_id,student_id,attendance_status,lesson_content) values ('${id(101)}','${A}','present','추가 내용'),('${id(102)}','${A}','absent','보강 내용');`);}
async function corrections(n=1){await db.exec(`insert into correction_reports(id,student_id,correction_date,start_time,published,subject,correction_content) select md5('correction'||g)::uuid,'${A}',current_date,'14:00'::time+g*interval '1 minute',true,'수학','첨삭 내용' from generate_series(1,${n})g;`);}

test('new snapshot matches existing report JSON for regular, special and correction records',async()=>{
 await regular(3);await special();await corrections(2);
 await db.exec(`insert into lesson_homework_results(id,lesson_id,student_id,lesson_content,assigned_homework,inspection_status) values ('${id(110)}',md5('lesson1')::uuid,'${A}','개별 내용','개별 숙제','complete');
 insert into lesson_exam_results(id,lesson_id,student_id,score,max_score,exam_title) values ('${id(111)}',md5('lesson1')::uuid,'${A}',45,50,'Test exam');`);
 const result=await snapshot();
 const old=(await db.query('select family_completed_learning_reports($1,30) lessons,family_correction_reports($1,50) corrections',[A])).rows[0];
 assert.deepEqual(result.lessons,old.lessons);assert.deepEqual(result.corrections,old.corrections);
 assert.equal(result.lessons.find(x=>x.lessonContent==='개별 내용').exams[0].percent,90);
});
test('monthly snapshot does not truncate more than 30 lessons or 50 corrections',async()=>{
 await regular(65);await special();await corrections(75);
 const result=await snapshot();assert.equal(result.lessons.length,67);assert.equal(result.corrections.length,75);
 assert.equal((await db.query('select jsonb_array_length(family_completed_learning_reports($1,30)) n',[A])).rows[0].n,30);
});
test('completed records survive absent enrollment but drafts and missing attendance stay private',async()=>{
 await regular(3);await special();await corrections(2);
 await db.exec(`update lessons set status='scheduled' where id=md5('lesson1')::uuid;
 delete from attendance where lesson_id=md5('lesson2')::uuid;
 update teacher_special_lessons set status='scheduled' where id='${id(102)}';
 update correction_reports set published=false where id=md5('correction1')::uuid;`);
 const result=await snapshot();assert.equal(result.lessons.length,2);assert.equal(result.corrections.length,1);
});
test('range includes both boundary days and excludes earlier and future records',async()=>{
 await regular(3);await corrections(2);await special();
 await db.exec(`update lessons set lesson_date=current_date-6 where id=md5('lesson1')::uuid;
 update lessons set lesson_date=current_date-7 where id=md5('lesson2')::uuid;
 update correction_reports set correction_date=current_date+1 where id=md5('correction2')::uuid;
 update teacher_special_lessons set lesson_date=current_date+1 where id='${id(102)}';`);
 const start=(await db.query('select (current_date-6)::text d')).rows[0].d;
 const end=(await db.query('select (current_date+1)::text d')).rows[0].d;
 const result=await snapshot(A,start,end);assert.equal(result.lessons.length,3);assert.equal(result.corrections.length,1);
 assert.ok(result.lessons.some(x=>x.lessonDate===start));assert.ok(result.lessons.some(x=>x.lessonDate===today));
});
test('guardian cannot request another family student or see their rows',async()=>{
 await regular(2,B);assert.equal((await snapshot()).lessons.length,0);
 await assert.rejects(snapshot(B),/연결된 자녀/);await assert.rejects(context(B),/연결된 자녀/);
 assert.deepEqual((await context()).children.map(x=>x.id),[A]);
});
test('student sees own records only and unlinked student cannot impersonate another',async()=>{
 await regular();await db.exec(`select set_config('test.uid','${id(41)}',false),set_config('test.role','student',false)`);
 assert.equal((await snapshot()).lessons.length,1);await assert.rejects(snapshot(B),/본인 학생/);
 await db.exec(`select set_config('test.uid','${id(99)}',false)`);
 await assert.rejects(snapshot(A),/본인 학생/);assert.equal((await snapshot(null)).lessons.length,0);
});
test('staff and anonymous callers are rejected; public and anon have no execute grant',async()=>{
 for(const role of ['teacher','admin','']){
  await db.query("select set_config('test.role',$1,false)",[role]);await assert.rejects(snapshot(),/학생 또는 학부모/);
 }
 const result=(await db.query(`select has_function_privilege('anon','family_summary_snapshot(uuid,date,date)','execute') a,has_function_privilege('authenticated','family_summary_snapshot(uuid,date,date)','execute') b,has_function_privilege('anon','family_student_context(uuid,boolean)','execute') c`)).rows[0];
 assert.deepEqual(result,{a:false,b:true,c:false});
});
test('invalid or unbounded date intervals fail instead of scanning all history',async()=>{
 await assert.rejects(snapshot(A,null,today),/조회 기간/);
 await assert.rejects(snapshot(A,'2000-01-01',today),/조회 기간/);
 await assert.rejects(snapshot(A,today,'2000-01-01'),/조회 기간/);
});
test('context reads schedule only when requested and preserves assignment/date rules',async()=>{
 await db.exec(`insert into enrollments(student_id,class_id,status) values ('${A}','${C}','active');
 insert into class_schedules(id,class_id,weekday,start_time,end_time,valid_from,valid_until) values
 ('${id(201)}','${C}',1,'14:00','15:00',current_date-10,null),
 ('${id(202)}','${C}',2,'14:00','15:00',current_date-10,null),
 ('${id(203)}','${C}',3,'14:00','15:00',current_date-10,current_date-1);`);
 assert.equal((await context()).weekClasses.length,0);assert.equal((await context(A,true)).weekClasses.length,2);
 await db.exec(`insert into student_schedule_assignments(student_id,class_schedule_id) values ('${A}','${id(201)}')`);
 assert.deepEqual((await context(A,true)).weekClasses.map(x=>x.id),[id(201)]);
 assert.deepEqual(Object.keys(await context()).sort(),['children','role','selectedStudent','weekClasses']);
});
test('empty linked history is returned as arrays and includes the correct child',async()=>{
 const result=await snapshot();assert.equal(result.dashboard.selectedStudent.id,A);assert.deepEqual(result.lessons,[]);assert.deepEqual(result.corrections,[]);
});

const previousHomework=async(student,record,kind)=> (await db.query('select family_previous_homework($1,$2,$3) value',[student,record,kind])).rows[0].value;
test('previous homework survives a 90-day gap and prefers student-specific homework',async()=>{
 await regular(3);
 await db.exec(`update lessons set lesson_date=current_date-90,starts_at=(current_date-90)::timestamp where id=md5('lesson1')::uuid;
 update lessons set lesson_date=current_date-120,starts_at=(current_date-120)::timestamp where id=md5('lesson2')::uuid;
 insert into lesson_homework_results(lesson_id,student_id,assigned_homework) values(md5('lesson1')::uuid,'${A}','개별 지난 숙제');`);
 const record=(await db.query("select md5('lesson3')::uuid id")).rows[0].id;
 assert.equal(await previousHomework(A,record,'lesson'),'개별 지난 숙제');
 await db.exec("update lessons set status='scheduled' where id=md5('lesson1')::uuid");
 assert.equal(await previousHomework(A,record,'lesson'),'공통 숙제');
});
test('previous correction homework ignores private records and another student',async()=>{
 await corrections(3);
 await db.exec(`update correction_reports set correction_date=current_date-100,homework_instruction='오래된 첨삭 과제' where id=md5('correction1')::uuid;
 update correction_reports set correction_date=current_date-10,homework_instruction='비공개',published=false where id=md5('correction2')::uuid;`);
 const record=(await db.query("select md5('correction3')::uuid id")).rows[0].id;
 assert.equal(await previousHomework(A,record,'correction'),'오래된 첨삭 과제');
 await assert.rejects(previousHomework(B,record,'correction'),/연결된 자녀/);
 await db.exec(`update correction_reports set student_id='${B}' where id=md5('correction1')::uuid`);
 assert.equal(await previousHomework(A,record,'correction'),'');
});
test('current-record ownership and publication are required for homework access',async()=>{
 await regular(2,B);const record=(await db.query("select md5('lesson2')::uuid id")).rows[0].id;
 await assert.rejects(previousHomework(A,record,'lesson'),/공개된 수업/);
 await assert.rejects(previousHomework(A,record,'other'),/지원하지/);
 assert.equal((await db.query("select has_function_privilege('anon','family_previous_homework(uuid,uuid,text)','execute') allowed")).rows[0].allowed,false);
});
test('special homework uses matching teacher, subject and lesson kind across long gaps',async()=>{
 await special();
 await db.exec(`insert into teacher_special_lessons(id,lesson_date,starts_at,kind,status) values ('${id(103)}',current_date-100,'15:00','extra','completed'),('${id(104)}',current_date-10,'15:00','makeup','completed');
 insert into teacher_special_lesson_students(session_id,student_id,assigned_homework) values ('${id(103)}','${A}','이전 추가수업 숙제'),('${id(104)}','${A}','다른 종류 숙제');`);
 assert.equal(await previousHomework(A,id(101),'lesson'),'이전 추가수업 숙제');
});
