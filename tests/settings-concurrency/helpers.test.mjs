import test from 'node:test';
import assert from 'node:assert/strict';
import {settingsChanges,mergeSettingsChoices,classSettingsValues,calendarValues} from '../../app/settings-concurrency.ts';
test('database JSON key order does not create phantom schedule changes',()=>{
 assert.deepEqual(settingsChanges({schedules:[{endTime:'19:00',weekday:1,startTime:'17:30'}]},{schedules:[{weekday:1,startTime:'17:30',endTime:'19:00'}]}),{});
});
test('unchanged normalized schedule and teacher order produce no edit',()=>{
 const a={name:' A ',subjectId:'s',room:null,color:'#123456',teachers:[{id:'b'},{id:'a'}],schedules:[{weekday:2,startTime:'17:30:00',endTime:'19:00:00'}]};
 assert.deepEqual(settingsChanges(classSettingsValues(a),classSettingsValues({...a,teachers:[...a.teachers].reverse()})),{});
});
test('different field edits retain both changes',()=>{
 const base={name:'A',room:'1'},mine={...base,name:'B'},latest={...base,room:'2'};
 assert.deepEqual(mergeSettingsChoices(base,mine,latest,{}),{name:'B',room:'2'});
});
test('per-field comparison applies remote choice without losing other local edits',()=>{
 const base={name:'A',room:'1',color:'red'},mine={...base,name:'B',color:'blue'},latest={...base,name:'C',room:'2'};
 assert.deepEqual(mergeSettingsChoices(base,mine,latest,{name:'latest'}),{name:'C',room:'2',color:'blue'});
 assert.equal(mine.name,'B');
});
test('calendar date/time and scope/category remain coherent groups',()=>{
 const v={scope:'school',category:'exam',startsOn:'2026-09-12',endsOn:'2026-09-12',startsAt:null,endsAt:null,school:'School',grade:null,title:'Test',classId:null,teacherId:null,note:null,contactName:null,contactPhone:null,location:null,status:'scheduled'};
 const base=calendarValues(v),next=calendarValues({...v,startsOn:'2026-09-13',endsOn:'2026-09-13',note:' memo '});
 assert.deepEqual(Object.keys(settingsChanges(base,next)),['timing','note']);
 assert.deepEqual(base.timing,{startsOn:'2026-09-12',endsOn:'2026-09-12',startsAt:'',endsAt:''});
 assert.equal(next.note,'memo');
});
