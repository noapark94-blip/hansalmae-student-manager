import {readFileSync} from 'node:fs';import vm from 'node:vm';import ts from 'typescript';import test from 'node:test';import assert from 'node:assert/strict';
const source=readFileSync(new URL('../../app/family-learning-report-feed.tsx',import.meta.url),'utf8');
const transpile=s=>ts.transpile(s,{target:ts.ScriptTarget.ES2022});const tick=()=>new Promise(r=>setImmediate(r));
function harness(){
 const state={},pending=[];let cleanup;
 const ctx={useEffect:f=>cleanup=f(),feedGeneration:{current:0},refreshInFlight:{current:false},refreshCompleteTimer:{current:null},window:{clearTimeout:()=>{}},detailDate:undefined,recordMonth:null,retryAttempt:0,detailOnly:false,studentId:'a',supabase:{rpc:()=>new Promise((resolve,reject)=>pending.push({resolve,reject}))},normalizeCorrectionReport:x=>x};
 for(const name of ['Refreshing','RefreshError','RefreshComplete','Loading','Unavailable','ReadTracking','Items','Reads','Corrections','CorrectionReads','Selected'])ctx['set'+name]=v=>{state[name]=v};
 ctx.setRetryAttempt=f=>ctx.retryAttempt=f(ctx.retryAttempt);
 const a=source.indexOf('  useEffect(() => {\n    let active = true;'),b=source.indexOf('  useEffect(',a+20),r=source.indexOf('  const retryFeed ='),rEnd=source.indexOf('  const selectCalendarDate',r);
 vm.createContext(ctx);vm.runInContext(transpile(source.slice(r,rEnd)+';globalThis.retry=retryFeed;'),ctx);
 return {ctx,state,pending,mount(){cleanup?.();vm.runInContext(transpile(source.slice(a,b)),ctx);},cleanup:()=>cleanup?.()};
}
test('first-load failure can be retried on the same screen and a success restores records',async()=>{
 const h=harness();h.mount();await tick();h.pending.splice(0).forEach(p=>p.resolve({data:null,error:{message:'offline'}}));await tick();assert.equal(h.state.Unavailable,true);assert.equal(h.state.Loading,false);
 h.ctx.retry();assert.equal(h.ctx.retryAttempt,1);assert.equal(h.state.Loading,true);h.mount();await tick();h.pending.splice(0).forEach(p=>p.resolve({data:[{lessonId:'new'}],error:null}));await tick();h.pending.splice(0).forEach(p=>p.resolve({data:[],error:null}));await tick();assert.equal(h.state.Unavailable,false);assert.equal(h.state.Loading,false);assert.equal(h.state.Items[0].lessonId,'new');
});
test('retry invalidates a pending old response before the new result is applied',async()=>{
 const h=harness();h.mount();await tick();const old=h.pending.splice(0);h.ctx.retry();h.mount();await tick();old.forEach(p=>p.resolve({data:[{lessonId:'old'}],error:null}));await tick();assert.equal(h.state.Items.length,0);h.cleanup();h.pending.splice(0).forEach(p=>p.resolve({data:[],error:null}));await tick();assert.equal(h.state.Items.length,0);
});
test('initial, detail and calendar failures expose retry controls',()=>{assert.match(source,/if \(unavailable\) return[^\n]+onClick=\{retryFeed\}/);assert.match(source,/calendarError &&[^\n]+onClick=\{retryFeed\}/);assert.match(source,/if \(detailOnly && \(unavailable[^\n]+onClick=\{retryFeed\}/);assert.match(source,/\[calendarMonth, displayMode, retryAttempt, studentId, supabase\]/);});
