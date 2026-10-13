import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import ts from 'typescript';
const code=ts.transpileModule(fs.readFileSync(new URL('../../app/exam-library-model.ts',import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
const module={exports:{}};new Function('exports','module',code)(module.exports,module);const model=module.exports;
test('groups numbered questions while retaining choices and line breaks',()=>{const items=model.splitExamText('1. A passage.\n① First\n② Second\n2) Another passage.\n① Yes\n② No');assert.equal(items.length,2);assert.equal(items[0].passage,'A passage.');assert.equal(items[0].choices,'① First\n② Second');assert.equal(new Set(items.map(q=>q.id)).size,2);});
test('rejects empty questions and invalid diagram sources',()=>{const exam={...model.newExam(),title:'시험',school:'검증학교'};assert.ok(model.validateExam(exam));assert.equal(model.safeDiagram('javascript:alert(1)'),false);assert.equal(model.safeDiagram('data:image/svg+xml;base64,AAAA'),false);});
test('printing escapes source markup and preserves intended text formatting',()=>{const q={...model.newQuestion(),passage:'<script>alert(1)</script> **bold** __underline__',choices:'① A\n② B'};const html=model.questionHtml(q,0,false);assert.ok(!html.includes('<script>'));assert.ok(html.includes('&lt;script&gt;'));assert.ok(html.includes('<u>underline</u>'));assert.ok(html.includes('<strong>bold</strong>'));assert.ok(html.includes('① A\n② B'));assert.ok(!html.includes('<b>정답</b>'));});
