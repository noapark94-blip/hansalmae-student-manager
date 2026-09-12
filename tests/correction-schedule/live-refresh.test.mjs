import test from 'node:test';
import assert from 'node:assert/strict';
import {createCorrectionRefreshQueue,replaceChangedAssignments} from '../../app/correction-live-refresh.ts';
const wait=()=>new Promise(resolve=>setTimeout(resolve,15));
test('100 duplicate change events coalesce into one batch',async()=>{
  const calls=[];const q=createCorrectionRefreshQueue(async b=>{calls.push(b)},assert.fail,{delay:1});
  for(let i=0;i<100;i++)q.request({id:'a'});
  q.request({id:'b'});q.request({assistants:true});await wait();q.dispose();
  assert.equal(calls.length,1);assert.deepEqual(calls[0],{full:false,assistants:true,ids:['a','b']});
});
test('changes during a request run once afterwards without overlap',async()=>{
  const calls=[];let release;
  const q=createCorrectionRefreshQueue(async b=>{calls.push(b);if(calls.length===1)await new Promise(r=>{release=r})},assert.fail,{delay:1});
  q.request({id:'a'});await wait();q.request({id:'b'});q.request({id:'b'});await wait();
  assert.equal(calls.length,1);release();await wait();q.dispose();
  assert.equal(calls.length,2);assert.deepEqual(calls[1].ids,['b']);
});
test('hidden tab holds changes until resume reconciliation',async()=>{
  let visible=false;const calls=[];const q=createCorrectionRefreshQueue(async b=>{calls.push(b)},assert.fail,{delay:1,visible:()=>visible});
  q.request({id:'a'});await wait();assert.equal(calls.length,0);
  visible=true;q.request({full:true});await wait();q.dispose();assert.equal(calls.length,1);assert.equal(calls[0].full,true);
});
test('failure does not cause retry loop; next request reconciles fully',async()=>{
  let count=0;const calls=[];const q=createCorrectionRefreshQueue(async b=>{calls.push(b);if(++count===1)throw Error('offline')},()=>{}, {delay:1});
  q.request({id:'a'});await wait();await wait();assert.equal(count,1);
  q.request({id:'b'});await wait();q.dispose();assert.equal(count,2);assert.equal(calls[1].full,true);
});
test('unmount cancels queued reads',async()=>{
  let count=0;const q=createCorrectionRefreshQueue(async()=>{count++},assert.fail,{delay:1});
  q.request({full:true});q.dispose();await wait();assert.equal(count,0);
});
test('delta removes deleted or out-of-week assignments and preserves untouched rows',()=>{
  const untouched={id:'b',note:'unchanged'};
  const result=replaceChangedAssignments({assignments:[{id:'a'},untouched],exceptions:[{assignmentId:'a'},{assignmentId:'b'}]}, {assignments:[{id:'c'}],exceptions:[]},['a','c']);
  assert.deepEqual(result,{assignments:[untouched,{id:'c'}],exceptions:[{assignmentId:'b'}]});
  assert.equal(result.assignments[0],untouched);
});
