// Pure preview checks; synthetic schedules only.
const assert=require('node:assert/strict'),esbuild=require('esbuild');
const bundled=esbuild.buildSync({entryPoints:['app/class-schedule-swap-model.ts'],bundle:true,platform:'node',format:'cjs',write:false});
const m={exports:{}};new Function('module','exports',bundled.outputFiles[0].text)(m,m.exports);
const {previewScheduleSwap:preview,isSwapScheduleAvailable:available}=m.exports;
const a={id:'a',classId:'a',className:'가상 영어',weekday:6,startTime:'14:00',endTime:'15:30',room:'101',teachers:[]};
const b={...a,id:'b',classId:'b',className:'가상 수학',startTime:'12:30',endTime:'14:00'};
const other={...a,id:'c',classId:'c',className:'가상 과학',startTime:'12:30',endTime:'14:00'};
assert.equal(preview(a,b,[a,b]).error,'');
assert.equal(preview(a,b,[a,b,{...other,validUntil:'2000-01-01'}]).error,'');
assert.equal(preview(a,b,[a,b,{...other,active:false}]).error,'');
assert.equal(preview({...a,validUntil:'2090-01-01'},b,[{...other,validFrom:'2090-01-02'}]).error,'');
assert.match(preview(a,b,[a,b,other]).error,/가상 과학/);
assert.match(preview({...a,validUntil:'2000-01-01'},b,[a,b]).error,/종료된/);
assert.equal(available({...a,validUntil:'2026-09-19'},'2026-09-19'),true);
assert.equal(available({...a,validUntil:'2026-09-18'},'2026-09-19'),false);
assert.match(preview({...a,validUntil:'2090-01-02'},b,[{...other,validFrom:'2090-01-02'}]).error,/가상 과학/);
console.log('PASS: swap preview excludes inactive/expired/non-overlapping schedules, includes boundary dates, blocks real overlaps and allows touching times.');
