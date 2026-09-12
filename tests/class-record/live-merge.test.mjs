import test from 'node:test';
import assert from 'node:assert/strict';
import {mergeLiveEditValues,editChanges} from '../../app/class-record-concurrency.ts';
const base={notice:'old',lessonContent:'lesson',students:{a:{note:'old',status:'present',exam_id:''}}};
test('live remote field merges while dirty field keeps old conflict baseline',()=>{
 const local=structuredClone(base);local.students.a.note='typing';
 const remote=structuredClone(base);remote.students.a.note='other teacher';remote.students.a.status='late';
 const r=mergeLiveEditValues(base,local,remote);
 assert.equal(r.values.students.a.note,'typing');assert.equal(r.values.students.a.status,'late');
 assert.equal(r.baseline.students.a.note,'old');assert.equal(r.baseline.students.a.status,'late');
 assert.equal(editChanges(r.baseline,r.values)[0].before,'old');
});
test('remote roster additions arrive and removed dirty student stays recoverable',()=>{
 const local=structuredClone(base);local.students.a.note='unsaved';
 const remote={notice:'old',lessonContent:'lesson',students:{b:{note:'new',status:'present',exam_id:''}}};
 const r=mergeLiveEditValues(base,local,remote);
 assert.equal(r.values.students.b.note,'new');assert.equal(r.values.students.a.note,'unsaved');
 assert.equal(r.baseline.students.a.note,'old');
});
test('clean deletion drops the removed student and clean updates adopt remote baseline',()=>{
 const remote={notice:'new notice',lessonContent:'lesson',students:{}};
 const r=mergeLiveEditValues(base,base,remote);
 assert.deepEqual(r.values,remote);assert.deepEqual(r.baseline,remote);
});
