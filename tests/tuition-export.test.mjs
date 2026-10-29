import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {createRequire} from 'node:module';
import ts from 'typescript';
import readXlsx from 'read-excel-file/node';
import {unzipSync,strFromU8} from 'fflate';
const require=createRequire(import.meta.url),cache={};
function load(name){if(cache[name])return cache[name];const m={};cache[name]=m;new Function('exports','require',ts.transpileModule(fs.readFileSync(new URL(`../app/${name}.ts`,import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText)(m,p=>p.startsWith('./tuition-export')?load(p.slice(2)):require(p));return m;}
const model=load('tuition-export-model'),{tuitionExcel}=load('tuition-export-excel');
const row={id:'c1',studentId:'s1',studentName:'=1+1 & 학생',school:'학교',grade:'고1',subjects:['영어'],classNames:['영어반'],lineItems:[{className:'고등 영어',amount:350000}],totalAmount:350000,paidAmount:300000,status:'partial',memo:'<확인>',month:'2026-09',payments:[{id:'p2',amount:200000,method:'transfer',paidAt:'2026-09-02T01:00:00Z'},{id:'p1',amount:100000,method:'card',paidAt:'2026-08-31T16:00:00Z'}]};
test('month bounds and Korean calendar dates',()=>{assert.deepEqual(model.monthsBetween('2026-12','2027-02'),['2026-12','2027-01','2027-02']);assert.deepEqual(model.monthsBetween('2026-10','2026-09'),[]);assert.deepEqual(model.monthsBetween('2024-01','2026-01'),[]);assert.equal(model.koreaDate(row.payments[1].paidAt),'2026-09-01');assert.equal(model.excelDate('invalid'),null);});
test('combined filters and waived outstanding',()=>{const f={query:'학생',school:'학교',grade:'고1',subject:'영어',status:'partial'};assert.equal(model.matchesExport(row,f),true);assert.equal(model.matchesExport(row,{...f,grade:'중1'}),false);assert.deepEqual(model.amounts({...row,status:'waived'}),{total:350000,paid:300000,waived:50000,balance:0});});
test('XLSX independent reader preserves dates, installment totals, literal names and selected columns',async()=>{
 const bytes=Buffer.from(tuitionExcel([row],['studentName','total','paid','balance','date','method']));
 const data=await readXlsx(bytes);
 assert.equal(data[4][0],'=1+1 & 학생');assert.equal(data[4][4].toISOString().slice(0,10),'2026-09-01');assert.equal(data[5][4].toISOString().slice(0,10),'2026-09-02');
 assert.equal(data[4][1],350000);assert.equal(data[5][1],null);assert.equal(data[4][2]+data[5][2],300000);assert.equal(data[4][3],50000);assert.equal(data[5][3],null);
 assert.deepEqual(data[3],['학생명','원비','납부액','미납액','납부일','결제방식']);
 const xml=strFromU8(unzipSync(bytes)['xl/worksheets/sheet1.xml']);assert.ok(!xml.includes('t="d"'));assert.ok(xml.includes('SUM(B5:B6)'));assert.ok(!xml.includes('<f>=1+1'));
});
test('multiple months, missing payments and no unselected students',async()=>{
 const waived={...row,id:'c2',month:'2026-10',status:'waived',paidAmount:0,payments:[]};
 const bytes=Buffer.from(tuitionExcel([waived],['studentName','waived','balance','date']));const data=await readXlsx(bytes);
 assert.equal(data[4][1],350000);assert.equal(data[4][2],0);assert.equal(data[4][3],null);
 const zip=unzipSync(tuitionExcel([row,waived],['studentName','paid']));assert.ok(zip['xl/worksheets/sheet2.xml']);assert.ok(strFromU8(zip['xl/workbook.xml']).includes('name="2026-10"'));
 assert.throws(()=>tuitionExcel([],['studentName']));assert.throws(()=>tuitionExcel([row],[]));
});
