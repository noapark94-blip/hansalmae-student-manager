import {readFileSync} from 'node:fs';import vm from 'node:vm';import ts from 'typescript';import test from 'node:test';import assert from 'node:assert/strict';
const code=path=>readFileSync(new URL('../../app/'+path,import.meta.url),'utf8');
const compile=s=>ts.transpile(s,{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.CommonJS});
const exports={};vm.runInNewContext(compile(code('family-calendar-selection.ts')),{exports});vm.runInNewContext(compile(code('family-detail-query.ts')),{exports});
const source=code('family-learning-report-feed.tsx');
test('month navigation preserves the day, clamps month end and crosses years',()=>{
 for(const [month,selected,want] of [['2026-08','2026-09-13','2026-08-13'],['2026-02','2026-01-31','2026-02-28'],['2024-02','2024-01-31','2024-02-29'],['2027-01','2026-12-31','2027-01-31'],['2025-12','2026-01-01','2025-12-01']])assert.equal(exports.calendarMonthSelection(month,selected),want);
});
test('actual navigation handler updates month, selected date and loading together',()=>{
 const state={};const ctx={calendarMonth:'2026-09',selectedDate:'2026-09-30',calendarMonthSelection:exports.calendarMonthSelection,setLoading:v=>state.loading=v,setCalendarScheduleLoading:v=>state.scheduleLoading=v,setSelected:v=>state.detail=v,setSelectedDate:v=>state.date=v,setCalendarMonth:v=>state.month=v};
 const a=source.indexOf('  const selectCalendarDate ='),b=source.indexOf('  useEffect(',a);vm.createContext(ctx);vm.runInContext(compile(source.slice(a,b)+';globalThis.move=navigateCalendarMonth;globalThis.pick=selectCalendarDate;'),ctx);
 ctx.move('2026-02');assert.equal(state.date,'2026-02-28');assert.equal(state.month,'2026-02');assert.equal(state.loading,true);assert.equal(state.detail,null);
 ctx.pick('2026-10-01');assert.equal(state.month,'2026-10');assert.equal(state.date,'2026-10-01');
});
test('lesson and correction details use an independent homework lookup, not the loaded month',()=>{
 assert.match(source,/useFamilyPreviousHomework\(supabase,studentId,item.lessonId,"lesson"\)/);
 assert.match(source,/useFamilyPreviousHomework\(supabase,studentId,item.id,"correction"\)/);
 assert.doesNotMatch(source,/function findPreviousLessonHomework/);
});
test('calendar details use date-based detail loading, with an independent key for each record',()=>{
 const a=source.indexOf('  if (displayMode === "calendar") return ('),b=source.indexOf('\n  return (',a),calendar=source.slice(a,b);
 assert.match(calendar,/<FamilyLearningReportFeed/);assert.match(calendar,/studentId=\{studentId\} detailOnly/);assert.equal((calendar.match(/date:selected.date/g)||[]).length,2);assert.doesNotMatch(calendar,/previousHomework=\{findPrevious/);assert.match(calendar,/onClick=\{\(\) => selectCalendarDate\(day.date\)\}/);
});
test('saved calendar lessons match by record identity, not just the displayed time',()=>{
 const a=source.indexOf('function calendarRecordMatchesSchedule('),b=source.indexOf('\nfunction feedFilterLabel',a);
 const context={formatTime:()=> '11:00',calendarItemTone:()=> 'regular'};vm.createContext(context);vm.runInContext(compile(source.slice(a,b)+';globalThis.match=calendarRecordMatchesSchedule;'),context);
 const item={kind:'lesson',time:'11:00',report:{lessonId:'saved-a'}};
 assert.equal(context.match(item,{id:'regular-saved:saved-a',startTime:'14:00',kind:'regular'}),true);
 assert.equal(context.match(item,{id:'regular-saved:saved-b',startTime:'11:00',kind:'regular'}),false);
 assert.equal(context.match(item,{id:'special:saved-b',startTime:'11:00',kind:'extra'}),false);
});
