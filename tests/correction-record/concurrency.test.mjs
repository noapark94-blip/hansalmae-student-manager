import test from 'node:test';
import assert from 'node:assert/strict';
import {conflictingReportFields,resolveReportChoices,mergeRemoteReport,mergeRemoteBaseline} from '../../app/correction-record-concurrency.ts';
test('different fields merge without comparison',()=>{
 const base={examScore:70,evaluation:'old'};const local={...base,examScore:90};const remote={...base,evaluation:'new'};
 assert.deepEqual(conflictingReportFields(base,local,remote),[]);
 assert.deepEqual(resolveReportChoices(base,local,local,remote,{}),{examScore:90,evaluation:'new'});
});
test('same values are not conflicts',()=>assert.deepEqual(conflictingReportFields({examScore:70},{examScore:90},{examScore:90}),[]));
test('mixed per-field choices preserve unrelated local input',()=>{
 const base={examScore:70,evaluation:'old',correctionContent:'old task'};
 const local={examScore:90,evaluation:'mine',correctionContent:'my task'};
 const remote={examScore:85,evaluation:'theirs',correctionContent:'old task'};
 assert.deepEqual(conflictingReportFields(base,local,remote),['examScore','evaluation']);
 assert.deepEqual(resolveReportChoices(base,local,local,remote,{examScore:'latest',evaluation:'mine'}),{examScore:85,evaluation:'mine',correctionContent:'my task'});
 assert.equal(local.examScore,90);assert.equal(base.examScore,70);
});
test('typing after comparison snapshot survives applying a choice',()=>{
 assert.equal(resolveReportChoices({evaluation:'old'},{evaluation:'mine'},{evaluation:'new typing'},{evaluation:'theirs'},{evaluation:'latest'}).evaluation,'new typing');
});
test('live update retains original baseline for dirty field',()=>{
 const base={examScore:70,evaluation:'old'},local={examScore:90,evaluation:'old'},remote={examScore:85,evaluation:'new'};
 assert.deepEqual(mergeRemoteBaseline(local,base,remote),{examScore:70,evaluation:'new'});
 assert.deepEqual(mergeRemoteReport(local,base,remote),{examScore:90,evaluation:'new'});
});
test('save response preserves later input and adopts saved metadata',()=>{
 assert.deepEqual(mergeRemoteReport({examScore:95},{examScore:90},{id:'saved',examScore:90,published:true}),{id:'saved',examScore:95,published:true});
});
test('empty fields use consistent defaults',()=>assert.deepEqual(conflictingReportFields({}, {examScore:null,examMaxScore:100,evaluation:''},{}),[]));
