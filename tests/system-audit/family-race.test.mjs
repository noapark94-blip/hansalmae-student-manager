import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';
import test from 'node:test';
import assert from 'node:assert/strict';
const cacheExports={};
vm.runInNewContext(ts.transpile(readFileSync(new URL('../../app/family-page-cache.ts',import.meta.url),'utf8'),{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}),{exports:cacheExports});
const source=readFileSync(new URL('../../app/family-dashboard.tsx',import.meta.url),'utf8');
function harness(name='FamilyLiveDashboard'){
 const pending=[]; const state={};
 const ctx={...cacheExports,profile:{id:'parent'},today:'2026-09-13',setDetailTarget:()=>{},useCallback:f=>f,requestVersion:{current:0},requestTarget:{current:null},supabase:{rpc:(_,p)=>new Promise((resolve,reject)=>pending.push({id:p.p_student_id,resolve,reject}))},setDashboard:v=>state.dashboard=v,setLessons:v=>state.lessons=v,setCorrections:v=>state.corrections=v,setLoading:v=>state.loading=v,setError:v=>state.error=v,setData:f=>state.data=typeof f==='function'?f(state.data):f,setSelectedId:v=>state.selected=v,onStudentChange:v=>state.parent=v,setTodayLessons:f=>state.lessons=typeof f==='function'?f(state.lessons):f};
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
  const answer=item=>({data:nameResponse(view,item.id),error:null});
  for(const item of h.pending.filter(x=>x.id==='b'))item.resolve(answer(item));
  await new Promise(resolve=>setImmediate(resolve));
  for(const item of h.pending.filter(x=>x.id==='b'))item.resolve(answer(item));
  await b;
  for(const item of h.pending.filter(x=>x.id==='a'))item.resolve(answer(item));
  await a;assert.equal(h.state.parent,'b');
 });
}
test('summary snapshot updates the student and both record groups together',async()=>{
 const h=harness('FamilySummaryReportView');const a=h.ctx.run('a'),b=h.ctx.run('b');
 h.pending.find(x=>x.id==='b').resolve({data:nameResponse('FamilySummaryReportView','b'),error:null});await b;
 h.pending.find(x=>x.id==='a').resolve({data:nameResponse('FamilySummaryReportView','a'),error:null});await a;
 assert.equal(h.state.parent,'b');assert.equal(h.state.lessons[0].id,'b');assert.equal(h.state.corrections[0].id,'b');
});
function nameResponse(view,id){return view==='FamilySummaryReportView'?{dashboard:{selectedStudent:{id}},lessons:[{id}],corrections:[{id}]}:{selectedStudent:{id}};}

for(const view of ['FamilyLiveDashboard','FamilyScheduleView','FamilyCalendarView','FamilySummaryReportView']){
 test(view+' restores matching cached content while still refreshing on revisit',async()=>{
  const h=harness(view);const a=h.ctx.run('a');
  for(const p of h.pending)p.resolve(view==='FamilyLiveDashboard'?response('a'):{data:nameResponse(view,'a'),error:null});
  await a;const count=h.pending.length;const revisit=h.ctx.run('a');
  assert.ok(h.pending.length>count,'revisit must revalidate');
  assert.equal((h.state.data??h.state.dashboard).selectedStudent.id,'a');
  for(const p of h.pending.slice(count))p.resolve(view==='FamilyLiveDashboard'?response('a'):{data:nameResponse(view,'a'),error:null});await revisit;
 });
 test(view+' late response after session invalidation cannot update the page',async()=>{
  const h=harness(view);const a=h.ctx.run('a');h.ctx.clearFamilyPageCache(h.ctx.supabase);
  for(const p of h.pending)p.resolve(view==='FamilyLiveDashboard'?response('a'):{data:nameResponse(view,'a'),error:null});await a;assert.equal(h.state.parent,undefined);
 });
 test(view+' rejected network request ends loading and can be retried',async()=>{
  const h=harness(view);const a=h.ctx.run('a');for(const p of h.pending)p.reject(new Error('offline'));await a;
  assert.equal(h.state.loading,false);assert.match(h.state.error,/다시 시도/);
  const count=h.pending.length,b=h.ctx.run('b');for(const p of h.pending.slice(count))p.resolve(view==='FamilyLiveDashboard'?response('b'):{data:nameResponse(view,'b'),error:null});await b;assert.equal(h.state.parent,'b');
 });
}

for(const view of ['FamilyLiveDashboard','FamilyScheduleView','FamilyCalendarView','FamilySummaryReportView']){
 for(const [label,error,preserve] of [['network error object',{message:'TypeError: Failed to fetch',code:''},true],['authorization error',{message:'연결된 자녀만 확인할 수 있습니다.',code:'P0001'},false]]){
  test(view+' handles '+label+' without confusing it with an empty result',async()=>{
   const h=harness(view);const first=h.ctx.run('a');
   for(const p of h.pending)p.resolve(view==='FamilyLiveDashboard'?response('a'):{data:nameResponse(view,'a'),error:null});await first;
   const count=h.pending.length;const refresh=h.ctx.run('a',view==='FamilyLiveDashboard');
   for(const p of h.pending.slice(count))p.resolve({data:null,error});await refresh;
   assert.equal(Boolean(h.state.data??h.state.dashboard),preserve);assert.equal(h.state.loading,false);assert.ok(h.state.error);
  });
 }
}
