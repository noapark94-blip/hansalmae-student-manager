import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createRequire} from 'node:module';
import ts from 'typescript';
const require=createRequire(import.meta.url);
const compile=(file)=>ts.transpileModule(fs.readFileSync(new URL(file,import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,jsx:ts.JsxEmit.ReactJSX}}).outputText;
const modelModule={exports:{}};new Function('exports','module',compile('../../app/exam-library-model.ts'))(modelModule.exports,modelModule);const model=modelModule.exports;
function editorHarness(){
 const slots=[];let cursor=0;
 const hooks={useState(initial){const i=cursor++;if(!(i in slots))slots[i]=typeof initial==='function'?initial():initial;return [slots[i],value=>{slots[i]=typeof value==='function'?value(slots[i]):value;}];},useRef(initial){const i=cursor++;return slots[i]??(slots[i]={current:initial});},useEffect(){},useCallback(fn){return fn;},useMemo(fn){return fn();}};
 const mod={exports:{}};
 const deps=(name)=>name==='react'?hooks:name==='react/jsx-runtime'?require(name):name==='./exam-library-model'?model:name.endsWith('.css')?{default:new Proxy({},{get:(_,key)=>String(key)})}:{};
 new Function('exports','module','require',compile('../../app/exam-library.tsx')+'\nexports.TestEditor=ExamEditor;')(mod.exports,mod,deps);
 const props={initial:model.newExam(),supabase:{},onClose(){},onSaved(){}};
 const render=()=>{cursor=0;return mod.exports.TestEditor(props);};
 return {render};
}
function nodes(tree){if(!tree||typeof tree!=='object')return [];if(Array.isArray(tree))return tree.flatMap(nodes);return [tree,...nodes(tree.props?.children)];}
const sample=fs.readFileSync(new URL('./bulk-paste.md',import.meta.url),'utf8');
function paste(harness){const tree=harness.render();const field=nodes(tree).find(n=>n.props?.label?.startsWith('시험 전체 붙여넣기'));field.props.onChange(sample);return harness.render();}
function paper(tree){return nodes(tree).find(n=>n.type?.name==='ExamPaper');}
test('footer Next organizes pasted text before showing the complete paper',()=>{const h=editorHarness();const tree=paste(h);const footer=nodes(tree).find(n=>n.type==='footer');const next=nodes(footer).find(n=>n.type==='button'&&n.props.children==='전체 정리 · 시험지 보기');next.props.onClick();const view=h.render();assert.equal(paper(view).props.exam.questions.length,12);assert.ok(paper(view).props.exam.questions[0].passage.includes('Example passage A.'));assert.ok(paper(view).props.exam.questions[9].passage.includes('⑤ You would'));});
test('top question and exam-info tabs cannot bypass organization of pasted text',()=>{for(const target of [1,2]){const h=editorHarness();const tree=paste(h);const nav=nodes(tree).find(n=>n.type==='nav');const tabs=nodes(nav).filter(n=>n.type==='button');tabs[target].props.onClick();assert.equal(paper(h.render()).props.exam.questions.length,12);}});
test('returning to the source does not overwrite edited questions when text is unchanged',()=>{const h=editorHarness();let tree=paste(h);nodes(tree).find(n=>n.type==='footer').props.children.flat(Infinity).find(n=>n?.type==='button'&&n.props.children==='전체 정리 · 시험지 보기').props.onClick();tree=h.render();paper(tree).props.onEdit(0);tree=h.render();const prompt=nodes(tree).find(n=>n.props?.label==='문제 · 발문');prompt.props.onChange('수정한 발문');tree=h.render();nodes(nodes(tree).find(n=>n.type==='nav')).filter(n=>n.type==='button')[0].props.onClick();tree=h.render();nodes(nodes(tree).find(n=>n.type==='nav')).filter(n=>n.type==='button')[1].props.onClick();tree=h.render();const updated=nodes(tree).find(n=>n.props?.label==='문제 · 발문');assert.equal(updated.props.value,'수정한 발문');});
