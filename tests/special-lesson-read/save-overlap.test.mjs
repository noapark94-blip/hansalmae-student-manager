import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createRequire} from 'node:module';
import ts from 'typescript';
const require=createRequire(import.meta.url);
const code=ts.transpileModule(fs.readFileSync(new URL('../../app/teacher-special-lessons.tsx',import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,jsx:ts.JsxEmit.ReactJSX}}).outputText;
function nodes(tree){if(!tree||typeof tree!=='object')return [];if(Array.isArray(tree))return tree.flatMap(nodes);return [tree,...nodes(tree.props?.children)];}
function MilitaryTimeInput(){}
function harness(accept=true){
 const day=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Seoul',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
 const sessions=[{id:'existing',teacherId:'teacher',teacherName:'검증 선생님',date:day,startTime:'18:00:00',endTime:'19:00:00',subjectId:'english',subject:'영어',kind:'makeup',students:[{id:'other',name:'기존 학생',attendanceStatus:null}]}];
 const roster=[{id:'new',name:'새 학생',school:'검증학교',grade:'고2',attendanceStatus:null}];
 const subjects=[{id:'english',name:'영어',mainSubject:'영어',parentId:null}];
 const slots=[];let cursor=0,arrays=0;const calls=[],confirms=[];
 const hooks={useState(initial){const i=cursor++;if(!(i in slots)){slots[i]=Array.isArray(initial)?[sessions,roster,subjects][arrays++]:typeof initial==='function'?initial():initial;}return [slots[i],value=>{slots[i]=typeof value==='function'?value(slots[i]):value;}];},useRef(value){const i=cursor++;return slots[i]??(slots[i]={current:value});},useEffect(){},useCallback(fn){return fn;},useMemo(fn){return fn();}};
 const rpc=async(name,args)=>{calls.push({name,args});if(name==='staff_save_mixed_special_lesson'){if(!args.p_values.p_overlap_token)return {error:{code:'PT409',message:'학생 수업 겹침\n선생님 수업 겹침',details:'request-token'}};return {data:'new-session',error:null};}return {data:name==='staff_teacher_special_lessons'?sessions:roster,error:null};};
 const query={select(){return this;},eq(){return this;},order(){return this;},then(resolve){return Promise.resolve({data:subjects.map(s=>({...s,main_subject:s.mainSubject,parent_id:null})),error:null}).then(resolve);}};
 const deps=name=>name==='react'?hooks:name==='react/jsx-runtime'?require(name):name==='./app-dialog'?{appConfirm:async options=>{confirms.push(options);return accept;}}:name==='./military-time-input'?{MilitaryTimeInput,isMilitaryTime:v=>/^(?:[01]\d|2[0-3]):[0-5]\d$/.test(v)}:name==='./special-lesson-read-retry'?{retrySpecialRead:fn=>fn(),specialReadMessage:()=>''}:name.endsWith('.css')?{default:{}}:{};
 const mod={exports:{}};new Function('exports','module','require',code)(mod.exports,mod,deps);
 const render=()=>{cursor=0;return mod.exports.TeacherSpecialLessons({supabase:{rpc,from:()=>query},profile:{id:'teacher',role:'teacher'}});};
 return {render,calls,confirms};
}
function fill(h){let tree=h.render();nodes(tree).find(n=>n.type==='button'&&n.props.children==='＋ 일정 등록').props.onClick();tree=h.render();nodes(tree).find(n=>n.type==='select'&&n.props.required).props.onChange({target:{value:'english'}});tree=h.render();nodes(tree).filter(n=>n.type===MilitaryTimeInput)[0].props.onChange('18:00');tree=h.render();nodes(tree).filter(n=>n.type===MilitaryTimeInput)[1].props.onChange('19:00');tree=h.render();const choices=nodes(tree).find(n=>n.props?.className==='special-student-options');nodes(choices).find(n=>n.type==='button').props.onClick();return h.render();}
test('same teacher, subject and time keeps Save enabled for a separate student',()=>{const h=harness();const tree=fill(h);assert.ok(nodes(tree).some(n=>n.props?.children==='이 수업에 학생 추가'));const save=nodes(tree).find(n=>n.type==='button'&&n.props.children==='일정 저장');assert.equal(save.props.disabled,false);});
test('multiline overlap warning is confirmed and resubmitted with the request token',async()=>{const h=harness();const tree=fill(h);nodes(tree).find(n=>n.type==='form').props.onSubmit({preventDefault(){}});await new Promise(resolve=>setImmediate(resolve));const saves=h.calls.filter(c=>c.name==='staff_save_mixed_special_lesson');assert.equal(saves.length,2);assert.equal(h.confirms[0].copy,'학생 수업 겹침\n선생님 수업 겹침');assert.equal(saves[1].args.p_values.p_overlap_token,'request-token');assert.equal(saves[1].args.p_values.p_id,null);assert.deepEqual(saves[1].args.p_values.p_student_ids,['new']);});
test('canceling an overlap confirmation does not write or close the draft',async()=>{const h=harness(false);const tree=fill(h);nodes(tree).find(n=>n.type==='form').props.onSubmit({preventDefault(){}});await new Promise(resolve=>setImmediate(resolve));assert.equal(h.calls.filter(c=>c.name==='staff_save_mixed_special_lesson').length,1);assert.ok(nodes(h.render()).some(n=>n.type==='form'));});
