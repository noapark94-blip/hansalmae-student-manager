import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import test from 'node:test';
import ts from 'typescript';
const source=readFileSync(new URL('../../app/alimtalk-send-center.tsx',import.meta.url),'utf8');
const helpers=source.slice(source.indexOf('const kindLabel='),source.indexOf('export function AlimtalkSendCenter'))+source.slice(source.indexOf('function buildPreview'),source.indexOf('function Empty'))+';globalThis.preview=buildPreview;globalThis.lengthError=previewLengthError;globalThis.historyBody=buildHistoryBody;';
const ctx={};vm.createContext(ctx);vm.runInContext(ts.transpile(helpers,{target:ts.ScriptTarget.ES2022}),ctx);
const row={subject:'수학',source:'extra',lessonContent:'학교 교과서 문제 풀이',homeworkContent:'',examContent:'',attendance:{status:'present'},exams:[]};
const preview=(rows,type='daily')=>ctx.preview('학생','2026-09-12',type,rows);
test('lesson-only fallback moves content once and keeps class kind',()=>{const p=preview([row]);assert.equal(p.lesson,'- 수학 추가수업 · 출석');assert.match(p.learningDetails,/학교 교과서/);assert.equal(p.body.split(row.lessonContent).length-1,1)});
test('exam, homework and correction content preserve existing sections',()=>{for(const r of [{...row,examContent:'평가 내용'},{...row,homeworkContent:'숙제 내용'},{...row,source:'correction'}]){const p=preview([r]);assert.match(p.learningDetails,/<시험>|<숙제>|<첨삭 과제>/)}});
test('empty learning fields show the empty message regardless of attendance',()=>{for(const status of ['present','absent','excused']){const p=preview([{...row,lessonContent:'  ',attendance:{status,absenceReason:'감기'}}]);assert.equal(p.learningDetails,'등록된 학습 상세가 없습니다.')}});
test('absent students retain written lesson content in daily and weekly reports',()=>{
 for(const status of ['absent','excused'])for(const source of ['regular','extra','makeup'])for(const type of ['daily','weekly'])for(const homeworkContent of ['', '29p 오답']){
  const p=preview([{...row,source,homeworkContent,attendance:{status,absenceReason:'감기'}}],type);
  assert.match(p.lesson,/결석\(감기\)/);
  assert.equal(p.body.split(row.lessonContent).length-1,1);
  assert.ok(!p.learningDetails.includes('등록된 학습 상세가 없습니다.'));
  if(homeworkContent){assert.ok(p.lesson.includes(row.lessonContent));assert.ok(p.learningDetails.includes(homeworkContent));}
  else assert.ok(p.learningDetails.includes(row.lessonContent));
 }
});
test('absence does not hide exams or correction tasks',()=>{
 for(const r of [{...row,examContent:'평가 내용'},{...row,source:'correction'}]){
  const p=preview([{...r,attendance:{status:'absent'}}]);
  assert.match(p.learningDetails,/<시험>|<첨삭 과제>/);
 }
});
test('long content survives both layout paths',()=>{const content='수업 내용 '.repeat(40)+'마지막 문장';for(const homeworkContent of ['', '숙제']){const p=preview([{...row,lessonContent:content,homeworkContent}]);assert.ok(p.body.includes(content));assert.equal(ctx.lengthError(p),'')}});
test('weekly makeup labels remain visible',()=>{assert.equal(preview([{...row,source:'makeup'}],'weekly').lesson,'- 수학 보강 · 출석')});
test('over-limit content is preserved and rejected before sending',()=>{const p=preview([{...row,lessonContent:'가'.repeat(1100)}]);assert.match(p.learningDetails,/가{1100}/);assert.match(ctx.lengthError(p),/1,000자/);assert.ok(source.includes('if(lengthError)return lengthError;const{error}'))});
test('preview and outgoing learning summary share the same result',()=>{assert.ok(source.includes('learningSummary:itemPreview.learningDetails'))});
test('sent history retains the saved text',()=>{const body=ctx.historyBody({studentName:'학생',reportType:'daily',periodStart:'2026-09-12',templateVariables:{studentName:'학생',periodStart:'2026-09-12',periodEnd:'2026-09-12',lessonSummary:'원래 수업',attendanceSummary:'출석',learningSummary:'원래 상세'}});assert.match(body,/원래 수업/);assert.match(body,/원래 상세/)});

test('mixed attendance explicitly separates regular class and absent correction in both layouts',()=>{
 for(const homeworkContent of ['', '29p 오답']){
  const rows=[{...row,source:'correction',lessonContent:'',attendance:{status:'absent',absenceReason:'병원 방문'}},{...row,source:'regular',homeworkContent}];
  const p=preview(rows);
  assert.ok(p.lesson.startsWith('- 수학 수업 · 출석'));
  assert.match(p.lesson,/- 수학 첨삭 · 결석\(병원 방문\)/);
  assert.equal(p.attendance,'출석 1회 · 결석 1회');
  assert.equal(rows[0].source,'correction');
 }
});
test('late, unknown and legacy absent states are not presented as attendance',()=>{
 assert.match(preview([{...row,attendance:{status:'late',lateMinutes:10}}]).lesson,/지각\(10분\)/);
 assert.match(preview([{...row,attendance:null}]).lesson,/출결 미입력/);
 const p=preview([{...row,attendance:{status:'excused',absenceReason:'감기'}}]);
 assert.match(p.lesson,/결석\(감기\)/);assert.equal(p.attendance,'결석 1회');
});

test('exam feedback follows scores for every exam category and report period',()=>{
 for(const examType of ['영단어 시험','주간 시험','월간 시험','모의고사'])for(const type of ['daily','weekly']){
  const p=preview([{...row,exams:[{examType,examTitle:'범위',score:80,maxScore:100,evaluation:'재시험'}]}],type);
  assert.match(p.exam,/80\/100(?:개)? \(80점\)\n  피드백: 재시험/);assert.ok(p.learningDetails.includes(p.exam));assert.ok(p.body.includes(p.exam));
 }
});
test('feedback without a score never becomes a zero score',()=>{
 const p=preview([{...row,exams:[{examType:'영단어 시험',examTitle:'내신 단어 part2',score:null,maxScore:100,evaluation:'재시험'}]}]);
 assert.equal(p.exam,'- 수학: 영단어 시험(내신 단어 part2)\n  피드백: 재시험');assert.ok(!p.body.includes('0/100'));
});
test('empty feedback leaves the existing score format unchanged',()=>{
 for(const evaluation of [undefined,null,'',' \n '])assert.equal(preview([{...row,exams:[{examType:'영단어 시험',examTitle:'범위',score:0,maxScore:100,evaluation}]}]).exam,'- 수학: 영단어 시험(범위) 0/100개 (0점)');
});
test('multiline feedback is preserved and counted by the send length guard',()=>{
 const p=preview([{...row,exams:[{examType:'시험',examTitle:'',score:null,maxScore:100,evaluation:' 재시험\r\n\n 단어 복습 '+ '가'.repeat(1000)}]}]);
 assert.match(p.exam,/피드백: 재시험\n  단어 복습/);assert.match(ctx.lengthError(p),/1,000자/);
});
