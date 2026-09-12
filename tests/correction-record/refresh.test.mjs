import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import ts from 'typescript';
const source=await readFile(new URL('../../app/correction-report-refresh.ts',import.meta.url),'utf8');
const resolved=source.replace('"./correction-live-refresh"',JSON.stringify(new URL('../../app/correction-live-refresh.ts',import.meta.url).href));
const compiled=ts.transpileModule(resolved,{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}}).outputText;
const {createCorrectionReportRefresh}=await import('data:text/javascript;base64,'+Buffer.from(compiled).toString('base64'));
import {mergeRemoteReport,mergeRemoteBaseline} from '../../app/correction-record-concurrency.ts';
const wait=()=>new Promise(r=>setTimeout(r,20));
const record=i=>({assignmentId:String(i),date:'2026-09-12',startTime:'17:30:00'});
test('100 distinct events plus duplicates make one RPC, not 200',async()=>{
 let calls=0,applied=0,size=0;
 const q=createCorrectionReportRefresh(async records=>{calls++;size=records.length;return records.map(()=>({}))},records=>{applied+=records.length},assert.fail,{delay:1});
 for(let i=0;i<100;i++){q.changed(record(i));q.changed(record(i));}
 await wait();q.dispose();assert.equal(calls,1);assert.equal(size,100);assert.equal(applied,100);
});
test('events during slow read are serialized into the next batch',async()=>{
 let release;let calls=0;
 const q=createCorrectionReportRefresh(async records=>{calls++;if(calls===1)await new Promise(r=>{release=r});return records.map(()=>({}))},()=>{},assert.fail,{delay:1});
 q.changed(record(1));await wait();q.changed(record(2));q.changed(record(3));await wait();assert.equal(calls,1);
 release();await wait();q.dispose();assert.equal(calls,2);
});
test('server batch limit is respected for 501 records',async()=>{
 const sizes=[];const q=createCorrectionReportRefresh(async r=>{sizes.push(r.length);return r.map(()=>({}))},()=>{},assert.fail,{delay:1});
 for(let i=0;i<501;i++)q.changed(record(i));
 await wait();q.dispose();assert.deepEqual(sizes,[500,1]);
});
test('unmount drops an outstanding response',async()=>{
 let release,applied=0;const q=createCorrectionReportRefresh(async r=>{await new Promise(resolve=>{release=resolve});return r.map(()=>({}))},()=>{applied++},assert.fail,{delay:1});
 q.changed(record(1));await wait();q.dispose();release();await wait();assert.equal(applied,0);
});
test('hidden tab defers reads and resumes once',async()=>{
 let visible=false,calls=0;const q=createCorrectionReportRefresh(async r=>{calls++;return r.map(()=>({}))},()=>{},assert.fail,{delay:1,visible:()=>visible});
 q.changed(record(1));await wait();assert.equal(calls,0);visible=true;q.resume();await wait();q.dispose();assert.equal(calls,1);
});
test('partial response is not applied; next resume retries safely',async()=>{
 let calls=0,applied=0,errors=0;const q=createCorrectionReportRefresh(async r=>++calls===1?[]:r.map(()=>({})),()=>{applied++},()=>{errors++},{delay:1});
 q.changed(record(1));await wait();assert.equal(applied,0);assert.equal(errors,1);q.resume();await wait();q.dispose();assert.equal(applied,1);assert.equal(calls,2);
});
test('typing during batched read keeps original conflict baseline',async()=>{
 const base={evaluation:'old',examScore:70};let local={...base};let release;let values,saved;
 const q=createCorrectionReportRefresh(async()=>{await new Promise(r=>{release=r});return [{evaluation:'remote',examScore:80}]},(_records,rows)=>{values=mergeRemoteReport(local,base,rows[0]);saved=mergeRemoteBaseline(local,base,rows[0])},assert.fail,{delay:1});
 q.changed(record(1));await wait();local.evaluation='typing';release();await wait();q.dispose();
 assert.deepEqual(values,{evaluation:'typing',examScore:80});assert.deepEqual(saved,{evaluation:'old',examScore:80});
});
