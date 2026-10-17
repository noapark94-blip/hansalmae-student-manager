import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import ts from 'typescript';
const m = {exports:{}};
new Function('exports', ts.transpileModule(fs.readFileSync(new URL('../../app/planner/start-times-model.ts', import.meta.url),'utf8'), {compilerOptions:{module:ts.ModuleKind.CommonJS}}).outputText)(m.exports);
const {generateStartTimes:g,applyStartTimes:a}=m.exports;
test('90/120 minute schedules include only lessons finishing by 22:00',()=>{
 assert.deepEqual(g('16:00',90),['16:00','17:30','19:00','20:30']);
 assert.deepEqual(g('16:00',120),['16:00','18:00','20:00']);
 assert.deepEqual(g('09:30',120),['09:30','11:30','13:30','15:30','17:30','19:30']);
 assert.deepEqual(g('20:30',90),['20:30']);
 assert.deepEqual(g('20:31',90),[]);
 for(const time of ['', '25:00','16:90','9:30']) assert.deepEqual(g(time,90),[]);
 assert.deepEqual(g('16:00',0),[]);
});
test('batch application preserves unselected days and original input',()=>{
 const starts=['16:00','18:00','16:00','18:00','16:00','09:30,14:00',''];
 assert.deepEqual(a(starts,[0,2,4],g('16:00',120)),['16:00,18:00,20:00','18:00','16:00,18:00,20:00','18:00','16:00,18:00,20:00','09:30,14:00','']);
 assert.equal(starts[0],'16:00');
});

test('typed 24-hour times normalize without guessing invalid input',()=>{
 const normalize=m.exports.normalizeStartTime;
 for(const [input,expected] of [['1600','16:00'],['930','09:30'],['9:30','09:30'],['09:30','09:30'],[' 1600 ','16:00']])assert.equal(normalize(input),expected);
 for(const input of ['','16','24:00','25:30','16:60','오후 4시'])assert.equal(normalize(input),null);
});
