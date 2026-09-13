import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';
import test from 'node:test';
import assert from 'node:assert/strict';
const cacheExports={};
vm.runInNewContext(ts.transpile(readFileSync(new URL('../../app/family-page-cache.ts',import.meta.url),'utf8'),{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}),{exports:cacheExports});
const source=readFileSync(new URL('../../app/family-grades-view.tsx',import.meta.url),'utf8');
function harness(){
 const pending=[],state={},effects=[];
 const ctx={...cacheExports,profile:{id:'parent'},useRef:()=>({current:0}),useCallback:f=>f,useEffect:f=>effects.push(f),studentId:'a',supabase:{rpc:(name,args)=>new Promise((resolve,reject)=>pending.push({name,id:args.p_student_id,resolve,reject}))},setData:v=>state.data=v,setAcademic:v=>state.academic=v,setLoading:v=>state.loading=v,setError:v=>state.error=v,onStudentChange:v=>state.parent=v};
 const start=source.indexOf('  const requestVersion=');const end=source.indexOf('  const student=data?',start);
 vm.createContext(ctx);vm.runInContext(ts.transpile(source.slice(start,end)+';globalThis.run=load;globalThis.change=changeStudent;',{target:ts.ScriptTarget.ES2022}),ctx);
 const answer=(id,error=null)=>{for(const p of pending.filter(p=>p.id===id))p.resolve({data:error?null:p.name==='family_student_context'?{selectedStudent:{id}}:{records:[{id}]},error});};
 return {ctx,state,pending,effects,answer};
}
test('grades late child response cannot revert newer selection or records',async()=>{const h=harness();const a=h.ctx.run('a'),b=h.ctx.run('b');h.answer('b');await b;h.answer('a');await a;assert.equal(h.state.parent,'b');assert.equal(h.state.data.selectedStudent.id,'b');assert.equal(h.state.academic.records[0].id,'b')});
test('grades old error cannot replace new success',async()=>{const h=harness();const a=h.ctx.run('a'),b=h.ctx.run('b');h.answer('b');await b;h.answer('a',{message:'old error'});await a;assert.equal(h.state.error,'');assert.equal(h.state.loading,false)});
test('grades child selection invalidates pending response immediately',async()=>{const h=harness();const a=h.ctx.run('a');h.ctx.change('b');h.answer('a');await a;assert.equal(h.state.parent,'b');assert.equal(h.state.data,null);assert.equal(h.state.loading,true)});
test('grades effect cleanup blocks updates after leaving the page',async()=>{const h=harness();const cleanup=h.effects[0]();cleanup();h.answer('a');await new Promise(r=>setImmediate(r));assert.equal(h.state.parent,undefined);assert.equal(h.state.data,null)});
test('grades network rejection clears loading and permits a later retry',async()=>{const h=harness();const a=h.ctx.run('a');h.pending[0].reject(Error('offline'));h.pending[1].resolve({data:null});await a;assert.equal(h.state.loading,false);assert.match(h.state.error,/다시 시도/);const b=h.ctx.run('b');h.answer('b');await b;assert.equal(h.state.parent,'b');assert.equal(h.state.error,'')});
test('grades switching children clears previous records before new response',async()=>{const h=harness();const a=h.ctx.run('a');h.answer('a');await a;const b=h.ctx.run('b');assert.equal(h.state.data,null);assert.equal(h.state.academic,null);h.answer('b');await b;assert.equal(h.state.academic.records[0].id,'b')});
