import test from 'node:test';import assert from 'node:assert/strict';
import {assignmentValues,scheduleChanges,mergeScheduleChoices,slotMembershipChanges,exceptionValues} from '../../app/correction-schedule-concurrency.ts';
const base=assignmentValues({studentId:'s',subject:'영어',weekday:1,startTime:'17:30:00',endTime:'19:00:00',tutorId:'t',note:'old'});
test('only changed field is sent',()=>assert.deepEqual(scheduleChanges(base,{...base,note:'mine'}),{note:'mine'}));
test('time and teacher merge without losing either',()=>{
 const mine={...base,tutorId:'new teacher'},remote={...base,schedule:{weekday:3,startTime:'19:00',endTime:'20:30'}};
 assert.deepEqual(mergeScheduleChoices(base,mine,remote,{}),{...remote,tutorId:'new teacher'});
});
test('weekday and time stay together as one comparison field',()=>{
 const next={...base,schedule:{weekday:6,startTime:'09:30',endTime:'11:00'}};
 assert.deepEqual(Object.keys(scheduleChanges(base,next)),['schedule']);
});
test('choosing remote schedule preserves local memo',()=>{
 const mine={...base,schedule:{weekday:3,startTime:'19:00',endTime:'20:30'},note:'mine'},remote={...base,schedule:{weekday:5,startTime:'16:00',endTime:'17:30'}};
 assert.deepEqual(mergeScheduleChoices(base,mine,remote,{schedule:'latest'}),{...remote,note:'mine'});
 assert.equal(mine.schedule.weekday,3);
});
test('one assistant change does not replace other slots',()=>{
 const id='00000000-0000-0000-0000-000000000001';const before=new Set([`1-17:30-${id}`]);const after=new Set([...before,`3-19:00-${id}`]);
 assert.deepEqual(slotMembershipChanges(before,after),[{weekday:3,startTime:'19:00',assistantId:id,selected:true}]);
 assert.equal(slotMembershipChanges(before,before).length,0);
});
test('assistant removal only targets removed membership',()=>assert.deepEqual(slotMembershipChanges(new Set(['1-17:30-a','2-19:00-b']),new Set(['2-19:00-b'])),[{weekday:1,startTime:'17:30',assistantId:'a',selected:false}]));
test('exception time and blank memo normalization matches server',()=>assert.deepEqual(exceptionValues({assignmentId:'a',originalDate:'2026-09-12',kind:'move',targetDate:'2026-09-13',targetStartTime:'09:30:00',targetEndTime:'11:00:00',note:null}),{assignmentId:'a',originalDate:'2026-09-12',kind:'move',targetDate:'2026-09-13',targetStartTime:'09:30',targetEndTime:'11:00',note:''}));
