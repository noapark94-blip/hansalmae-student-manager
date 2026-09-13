import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';
import test from 'node:test';
import assert from 'node:assert/strict';
const source=readFileSync(new URL('../../app/family-dashboard.tsx',import.meta.url),'utf8');
function harness(name='FamilyLiveDashboard'){
 const pending=[]; const state={};
 const ctx={useCallback:f=>f,requestVersion:{current:0},requestTarget:{current:null},supabase:{rpc:(_,p)=>new Promise(resolve=>pending.push({id:p.p_student_id,resolve}))},setDashboard:v=>state.dashboard=v,setLessons:v=>state.lessons=v,setCorrections:v=>state.corrections=v,setLoading:v=>state.loading=v,setError:v=>state.error=v,setData:f=>state.data=typeof f==='function'?f(state.data):f,setSelectedId:v=>state.selected=v,onStudentChange:v=>state.parent=v,setTodayLessons:f=>state.lessons=typeof f==='function'?f(state.lessons):f};
 const start=source.indexOf('  const load = useCallback(',source.indexOf('export function '+name));
 const end=source.indexOf('  useEffect(',start);
 vm.createContext(ctx);vm.runInContext(ts.transpile(source.slice(start,end)+';globalThis.run=load',{target:ts.ScriptTarget.ES2022}),ctx);
 return {ctx,state,pending};
}
const response=id=>({data:{dashboard:{selectedStudent:{id}},todayLessons:[{id}]},error:null});
test('late response does not revert the selected child',async()=>{const h=harness();const a=h.ctx.run('a'),b=h.ctx.run('b');h.pending[1].resolve(response('b'));await b;h.pending[0].resolve(response('a'));await a;assert.equal(h.state.selected,'b');assert.equal(h.state.parent,'b');assert.equal(h.state.lessons[0].id,'b')});
test('old failure does not replace the latest successful state',async()=>{const h=harness();const a=h.ctx.run('a'),b=h.ctx.run('b');h.pending[1].resolve(response('b'));await b;h.pending[0].resolve({data:null,error:{message:'old failure'}});await a;assert.equal(h.state.error,'');assert.equal(h.state.loading,false)});
test('background refresh for an old child does not supersede a new selection',async()=>{const h=harness();const a=h.ctx.run('a');h.pending[0].resolve(response('a'));await a;const b=h.ctx.run('b');const refresh=h.ctx.run('a',true);await Promise.resolve();assert.equal(h.pending.length,2);h.pending[1].resolve(response('b'));await Promise.all([b,refresh]);assert.equal(h.state.selected,'b')});
test('unmounted request cannot update parent or view',async()=>{const h=harness();const a=h.ctx.run('a');h.ctx.requestVersion.current++;h.pending[0].resolve(response('a'));await a;assert.equal(h.state.parent,undefined)});

for(const view of ['FamilyScheduleView','FamilyCalendarView','FamilySummaryReportView']){
 test(view+' ignores the previous child response',async()=>{
  const h=harness(view);const a=h.ctx.run('a'),b=h.ctx.run('b');
  const answer=item=>({data:item.id==='b'?{selectedStudent:{id:'b'}}:{selectedStudent:{id:'a'}},error:null});
  for(const item of h.pending.filter(x=>x.id==='b'))item.resolve(answer(item));
  await new Promise(resolve=>setImmediate(resolve));
  for(const item of h.pending.filter(x=>x.id==='b'))item.resolve(answer(item));
  await b;
  for(const item of h.pending.filter(x=>x.id==='a'))item.resolve(answer(item));
  await a;assert.equal(h.state.parent,'b');
 });
}
test('summary details from the previous child cannot overwrite the latest details',async()=>{
 const h=harness('FamilySummaryReportView');const a=h.ctx.run('a');
 h.pending[0].resolve({data:{selectedStudent:{id:'a'}},error:null});
 await new Promise(resolve=>setImmediate(resolve));
 const b=h.ctx.run('b');h.pending.find(x=>x.id==='b').resolve({data:{selectedStudent:{id:'b'}},error:null});
 await new Promise(resolve=>setImmediate(resolve));
 for(const item of h.pending.filter(x=>x.id==='b'))item.resolve({data:[{id:'b'}],error:null});await b;
 for(const item of h.pending.filter(x=>x.id==='a'))item.resolve({data:[{id:'a'}],error:null});await a;
 assert.equal(h.state.parent,'b');assert.equal(h.state.lessons[0].id,'b');assert.equal(h.state.corrections[0].id,'b');
});
