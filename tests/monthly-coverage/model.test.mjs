import {readFileSync} from 'node:fs';import vm from 'node:vm';import ts from 'typescript';import assert from 'node:assert/strict';import test from 'node:test';
function moduleOf(source){const ctx={exports:{},Intl,Date};vm.createContext(ctx);vm.runInContext(ts.transpile(source,{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}),ctx);return ctx.exports;}
const model=moduleOf(readFileSync('app/makeup-month.ts','utf8'));const source=readFileSync('app/monthly-lesson-coverage.tsx','utf8');const {coverageStatus}=moduleOf(source.slice(source.indexOf('export function coverageStatus'),source.indexOf('export function MonthlyLessonCoverage')));
const absence={recordKind:'absence',missedDate:'2026-08-20',scheduledAt:'2026-09-02T09:00:00Z',status:'scheduled'};
test('absence stays in original month when makeup is next month',()=>{assert.equal(model.inMakeupScope(absence,'2026-08','month'),true);assert.equal(model.inMakeupScope(absence,'2026-09','month'),false);assert.equal(model.inMakeupScope(absence,'2026-09','pending'),true);});
test('completed and cancelled records leave carryover',()=>{for(const status of ['completed','cancelled'])assert.equal(model.inMakeupScope({...absence,status},'2026-09','pending'),false);});
test('standalone makeup uses Korea date at UTC month boundary',()=>{assert.equal(model.inMakeupScope({...absence,recordKind:'schedule',scheduledAt:'2026-08-31T16:00:00Z'},'2026-09','month'),true);});
test('all period retains old history and month movement crosses year',()=>{assert.equal(model.inMakeupScope(absence,'2027-01','all'),true);assert.equal(model.shiftMakeupMonth('2026-12',1),'2027-01');assert.equal(model.shiftMakeupMonth('2026-01',-1),'2025-12');});
const row={target:12,attended:7,planned:3,unrecorded:0};
test('shortfall shows forecast vs final',()=>{assert.equal(coverageStatus(row,false).label,'2회 부족 예상');assert.equal(coverageStatus({...row,planned:0},true).label,'5회 미달');});
test('missing attendance requires review rather than definitive shortfall',()=>{const s=coverageStatus({...row,unrecorded:2},true);assert.equal(s.kind,'check');assert.equal(s.gap,2);});
test('achieved, expected and excluded states',()=>{assert.equal(coverageStatus({...row,attended:12},false).kind,'good');assert.equal(coverageStatus({...row,planned:5},false).label,'달성 예정');assert.equal(coverageStatus({...row,target:0},false).label,'목표 제외');});
