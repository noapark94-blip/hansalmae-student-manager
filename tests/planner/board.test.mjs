import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import ts from 'typescript';
const cache={};function load(path){if(cache[path])return cache[path];const m={exports:{}};const file=new URL('../../app/'+path+'.ts',import.meta.url);new Function('exports','require',ts.transpileModule(fs.readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText)(m.exports,n=>load(path.slice(0,path.lastIndexOf('/')+1)+n.slice(2)));return cache[path]=m.exports;}
const {boardDayGroups,plannerPrintRows}=load('planner/board-model');
const print=load('timetable-print-model');
const course={id:'a',name:'중2 영어',subject:'영어',room:'1',teachers:['t'],students:[{id:'s1',name:'김학생',grade:'중2'}],duration:120,count:3,enabled:true,high:false};
const config={courses:[course,{...course,id:'b',teachers:['t2']}],teachers:[{id:'t',name:'선생님',days:[1,2,3,4,5,6,7]},{id:'t2',name:'다른 선생님',days:[1,2,3,4,5,6,7]}],starts:['16:00,18:00','18:00','16:00','18:00','16:00','09:30,11:30','09:30'],objective:'student'};
test('weekend starts do not create weekday blank rows; saved unusual times stay visible',()=>{
 const groups=boardDayGroups(config,[]);assert.deepEqual(groups[0].starts,[960,1080]);assert.deepEqual(groups[1].starts,[570,690]);
 assert.deepEqual(groups[1].days,[6,7]);
 assert.ok(boardDayGroups(config,[{classId:'a',day:1,start:840,end:960}])[0].starts.includes(840));
});
test('draft print includes students, exact times, selected teacher and draft notice',()=>{
 const meetings=[{classId:'a',day:6,start:570,end:690},{classId:'b',day:7,start:570,end:690}];
 const rows=plannerPrintRows(config,meetings,'t');assert.equal(rows.length,1);assert.equal(rows[0].weekday,6);assert.equal(rows[0].startTime,'09:30');assert.equal(rows[0].endTime,'11:30');assert.equal(rows[0].students[0].name,'김학생');
 const html=print.timetablePrintHtml(rows,print.timetableDefaults('초안'),'편성 초안','2026-10-17',undefined,'편성 초안 <확인>');
 assert.ok(html.includes('김학생'));assert.ok(html.includes('편성 초안 &lt;확인&gt;'));assert.ok(!html.includes(print.TIMETABLE_NOTE));
 assert.ok(print.timetableBodyHtml(rows,print.timetableDefaults('정규'),'정규','오늘').includes(print.TIMETABLE_NOTE));
});
