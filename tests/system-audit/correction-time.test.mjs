import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';
function moduleAt(path){const exports={};vm.runInNewContext(ts.transpile(readFileSync(new URL(path,import.meta.url),'utf8'),{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS}),{exports});return exports;}
const time=moduleAt('../../app/correction-time.ts');
const schedule=moduleAt('../../app/correction-schedule-concurrency.ts');
test('custom starts appear once in the right fixed band including boundaries and weekends',()=>{
 for(const [day,start,expected] of [[1,'16:30','16:00'],[1,'17:29','16:00'],[1,'17:30','17:30'],[6,'12:00','11:00'],[7,'08:00','09:30'],[1,'22:30','20:30']]){
  assert.equal(time.correctionBucket(day,start),expected);
  assert.equal(time.correctionSlots(day).filter(s=>s[0]===time.correctionBucket(day,start)).length,1);
 }
});
test('end-only exceptions stay visible and invalid or overnight times are rejected',()=>{
 assert.equal(time.isStandardCorrectionTime(1,'16:00:00','17:30:00'),true);
 assert.equal(time.isStandardCorrectionTime(1,'16:00','18:00'),false);
 assert.equal(time.defaultCorrectionEnd('16:30'),'18:00');
 assert.equal(time.defaultCorrectionEnd('23:00'),'');
 for(const pair of [['16:30','16:30'],['18:00','16:30'],['23:00','00:30'],['','18:00'],['24:00','25:00']])assert.equal(time.validCorrectionTime(...pair),false);
 assert.equal(time.validCorrectionTime('16:30','18:00'),true);
});
test('actual edit form preserves existing custom start and end when saving',async()=>{
 const source=readFileSync(new URL('../../app/correction-management-board.tsx',import.meta.url),'utf8');
 const component=source.slice(source.indexOf('function AssignmentEditor('),source.indexOf('\nfunction ScheduleActionModal('));
 const calls=[];let saved=0;
 const context={exports:{},...time,...schedule,days:['월','화','수','목','금','토','일'],findSlot:(d,t)=>time.correctionBucket(d,t??'14:30'),useState:v=>[typeof v==='function'?v():v,()=>{}],useRef:v=>({current:v}),useMemo:f=>f(),useEffect:()=>{},CorrectionTimePicker:()=>null,confirmStyles:{},React:{createElement:(type,props,...children)=>({type,props:props??{},children})},window:{dispatchEvent:()=>{}},Event:class{}};
 vm.runInNewContext(ts.transpile(component+'\nexports.Editor=AssignmentEditor;',{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.React}),context);
 const row={id:'a',studentId:'s',studentName:'테스트',subject:'영어',weekday:3,startTime:'16:30:00',endTime:'18:00:00'};
 const tree=context.exports.Editor({row,data:{students:[{id:'s',name:'테스트'}],staff:[]},supabase:{rpc:async(name,args)=>{calls.push({name,args});return {data:{saved:true,values:schedule.assignmentValues(row)}};}},onClose:()=>{},onSaved:async()=>saved++});
 function find(node,type){if(!node||typeof node!=='object')return; if(node.type===type)return node;for(const c of (node.children??[]).flat(Infinity)){const found=find(c,type);if(found)return found;}}
 await find(tree,'form').props.onSubmit({preventDefault(){}});
 assert.equal(saved,1);assert.equal(calls[0].name,'staff_patch_correction_assignment');
 assert.equal(calls[0].args.p_base.schedule.startTime,'16:30');
 assert.equal(Object.keys(calls[0].args.p_changes).length,0,'saving an unchanged custom schedule must not reset its times');
});
