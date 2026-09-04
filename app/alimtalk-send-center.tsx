"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { StudentRow } from "./supabase";
import { HansalmaeIcon } from "./hansalmae-icons";
import styles from "./alimtalk-send-center.module.css";

type ReportType="daily"|"weekly";
type ListMode="ready"|"sent";
type Lesson={lessonId:string;lessonDate:string;className:string;subject:string;source:"regular"|"makeup"|"extra"|"correction";lessonContent:string;homeworkContent:string;examContent:string;attendance:{status:string;lateMinutes:number|null}|null;exams:{examType:string;examTitle:string;score:number|null;maxScore:number}[]};
type Recipient={guardianName:string;maskedPhone:string;available:boolean};
type History={id:string;studentId:string;studentName:string;reportType:ReportType;periodStart:string;status:string;sentAt:string|null;errorMessage:string|null};
type Preview={lesson:string;attendance:string;exam:string;homework:string;body:string};
type MissingItem={kind:string;title:string;date:string;time:string};
type ReadyStudent={studentId:string;studentName:string;school:string;grade:string;expectedCount:number;completedCount:number;complete:boolean;missingItems:MissingItem[];lessons:Lesson[];recipient:Recipient};

const kindLabel={regular:"정규",makeup:"보강",extra:"추가",correction:"첨삭"};
const attendanceLabel:Record<string,string>={present:"출석",late:"지각",absent:"결석",excused:"인정결석",scheduled:"예정"};

export function AlimtalkSendCenter({supabase}:{supabase:SupabaseClient;students:StudentRow[]}){
  const [type,setType]=useState<ReportType>("daily");
  const [listMode,setListMode]=useState<ListMode>("ready");
  const [anchor,setAnchor]=useState(today());
  const [query,setQuery]=useState("");
  const [studentId,setStudentId]=useState("");
  const [readyStudents,setReadyStudents]=useState<ReadyStudent[]>([]);
  const [checked,setChecked]=useState<Set<string>>(new Set());
  const [history,setHistory]=useState<History[]>([]);
  const [loading,setLoading]=useState(true);
  const [sending,setSending]=useState(false);
  const [confirming,setConfirming]=useState(false);
  const [incompletePrompt,setIncompletePrompt]=useState<{row:ReadyStudent;action:"select"|"send"}|null>(null);
  const [message,setMessage]=useState("");
  const period=useMemo(()=>periodFor(type,anchor),[type,anchor]);
  const historyMap=useMemo(()=>new Map(history.filter(item=>item.reportType===type&&item.periodStart===period.start).map(item=>[item.studentId,item])),[history,period.start,type]);
  const readyRows=useMemo(()=>readyStudents.filter(item=>historyMap.get(item.studentId)?.status!=="sent"),[historyMap,readyStudents]);
  const sentRows=useMemo(()=>history.filter(item=>item.reportType===type&&item.periodStart===period.start&&item.status==="sent"),[history,period.start,type]);
  const visibleStudents=useMemo(()=>readyRows.filter(item=>!query.trim()||[item.studentName,item.school,item.grade].some(value=>value.toLowerCase().includes(query.trim().toLowerCase()))),[query,readyRows]);
  const visibleSentRows=useMemo(()=>sentRows.filter(item=>!query.trim()||item.studentName.toLowerCase().includes(query.trim().toLowerCase())),[query,sentRows]);
  const selectedId=readyRows.some(item=>item.studentId===studentId)?studentId:readyRows[0]?.studentId??"";
  const student=readyRows.find(item=>item.studentId===selectedId);
  const preview=useMemo(()=>buildPreview(student?.studentName??"학생",period.start,type,student?.lessons??[]),[period.start,student,type]);
  const sentRecord=historyMap.get(selectedId);
  const checkedRows=readyStudents.filter(item=>checked.has(item.studentId)&&historyMap.get(item.studentId)?.status!=="sent"&&item.recipient.available&&item.completedCount>0);

  const loadHistory=useCallback(async()=>{const{data}=await supabase.rpc("staff_alimtalk_delivery_list");setHistory((data??[]) as History[])},[supabase]);
  useEffect(()=>{let active=true;void supabase.rpc("staff_alimtalk_delivery_list").then(({data})=>{if(active)setHistory((data??[]) as History[])});return()=>{active=false}},[supabase]);
  const loadReady=useCallback(async()=>{setLoading(true);setMessage("");const{data,error}=await supabase.rpc("staff_alimtalk_ready_students",{p_from:period.start,p_to:period.end});if(error){setReadyStudents([]);setChecked(new Set());setMessage(error.message)}else{const rows=(data??[]) as ReadyStudent[];setReadyStudents(rows);setStudentId(current=>rows.some(row=>row.studentId===current)?current:rows[0]?.studentId??"");setChecked(new Set(rows.filter(row=>row.complete&&row.recipient.available).map(row=>row.studentId)))}setLoading(false)},[period.end,period.start,supabase]);
  useEffect(()=>{let active=true;void supabase.rpc("staff_alimtalk_ready_students",{p_from:period.start,p_to:period.end}).then(({data,error})=>{if(!active)return;if(error){setReadyStudents([]);setChecked(new Set());setMessage(error.message);setLoading(false);return}const rows=(data??[]) as ReadyStudent[];setReadyStudents(rows);setStudentId(rows[0]?.studentId??"");setChecked(new Set(rows.filter(row=>row.complete&&row.recipient.available).map(row=>row.studentId)));setLoading(false)});return()=>{active=false}},[period.end,period.start,supabase]);

  async function sendRow(row:ReadyStudent){const itemPreview=buildPreview(row.studentName,period.start,type,row.lessons);const{error}=await supabase.functions.invoke("send-learning-alimtalk",{body:{studentId:row.studentId,reportType:type,periodStart:period.start,periodEnd:period.end,lessonSummary:itemPreview.lesson,attendanceSummary:itemPreview.attendance,examSummary:itemPreview.exam,homeworkSummary:itemPreview.homework,learningSummary:buildLearningDetails(itemPreview.exam,itemPreview.homework)}});if(!error)return null;let text=error.message;const context=(error as{context?:Response}).context;if(context)try{const body=await context.clone().json() as{error?:string};if(body.error)text=body.error}catch{}return text}
  async function sendSelected(){if(!checkedRows.length)return;setSending(true);setConfirming(false);setMessage("");let sent=0;const failed:string[]=[];for(let index=0;index<checkedRows.length;index+=3){const batch=checkedRows.slice(index,index+3);const results=await Promise.all(batch.map(async row=>({row,error:await sendRow(row)})));for(const result of results){if(result.error)failed.push(`${result.row.studentName}: ${result.error}`);else sent+=1}}await loadHistory();setChecked(new Set(failed.map(line=>readyStudents.find(row=>line.startsWith(`${row.studentName}:`))?.studentId).filter(Boolean) as string[]));setMessage(failed.length?`${sent}명 발송 접수 · ${failed.length}명 실패 (${failed.slice(0,2).join(" / ")})`:`${sent}명 학부모님께 알림톡 발송을 접수했습니다.`);setSending(false)}
  async function sendCurrentConfirmed(row:ReadyStudent){setIncompletePrompt(null);setSending(true);setMessage("");const error=await sendRow(row);if(error)setMessage(error);else{setMessage(`${row.studentName} 학생 학부모님께 알림톡을 접수했습니다.`);await loadHistory()}setSending(false)}
  function sendCurrent(){if(!student)return;if(!student.complete){setIncompletePrompt({row:student,action:"send"});return}void sendCurrentConfirmed(student)}
  function resetPeriod(nextType?:ReportType,nextAnchor?:string){if(nextType)setType(nextType);if(nextAnchor)setAnchor(nextAnchor);setListMode("ready");setLoading(true);setReadyStudents([]);setChecked(new Set());setStudentId("");setMessage("")}
  function toggle(row:ReadyStudent){if(checked.has(row.studentId)){setChecked(current=>{const next=new Set(current);next.delete(row.studentId);return next});return}if(!row.complete){setIncompletePrompt({row,action:"select"});return}setChecked(current=>new Set(current).add(row.studentId))}
  function acceptIncomplete(){if(!incompletePrompt)return;if(incompletePrompt.action==="send"){void sendCurrentConfirmed(incompletePrompt.row);return}setChecked(current=>new Set(current).add(incompletePrompt.row.studentId));setIncompletePrompt(null)}
  const selectable=readyStudents.filter(row=>row.complete&&row.recipient.available&&historyMap.get(row.studentId)?.status!=="sent");
  const allSelected=selectable.length>0&&selectable.every(row=>checked.has(row.studentId));

  return <section className={styles.center}>
    <header className={styles.hero}><div><p>학부모 소통</p><h1>알림톡 발송</h1><span>완료된 학습기록을 짧게 정리해 발송 전 확인합니다.</span></div><i><HansalmaeIcon name="chat" size={27}/></i></header>
    <nav className={styles.tabs}><button className={type==="daily"?styles.active:""} onClick={()=>resetPeriod("daily")}>일간 기록 발송</button><button className={type==="weekly"?styles.active:""} onClick={()=>resetPeriod("weekly")}>주간 기록 발송</button></nav>
    <nav className={styles.listTabs} aria-label="알림톡 발송 목록 구분"><button className={listMode==="ready"?styles.listActive:""} onClick={()=>{setListMode("ready");setQuery("")}}><span>발송 준비</span><b>{readyRows.length}명</b></button><button className={listMode==="sent"?styles.listActive:""} onClick={()=>{setListMode("sent");setQuery("")}}><span>발송 완료</span><b>{sentRows.length}명</b></button></nav>
    <div className={styles.toolbar}><label><span>{type==="daily"?"기록 날짜":"주간 기준일"}</span><input type="date" value={anchor} onChange={event=>resetPeriod(undefined,event.target.value)}/></label><label className={styles.search}><span>{listMode==="ready"?"준비 학생 검색":"발송 완료 검색"}</span><i><HansalmaeIcon name="students" size={16}/><input value={query} onChange={event=>setQuery(event.target.value)} placeholder={listMode==="ready"?"이름·학교 검색":"학생 이름 검색"}/></i></label><div className={styles.period}><small>발송 기준</small><b>{formatPeriod(period.start,period.end)}</b></div><button className={styles.refresh} onClick={()=>void Promise.all([loadReady(),loadHistory()])}><HansalmaeIcon name="refresh" size={15}/> 대상·내역 새로고침</button></div>
    <div className={styles.summary}><div><small>예정 학생</small><b>{readyStudents.length}명</b><span>이 기간에 수업이 있음</span></div><div><small>기록 완료</small><b>{readyStudents.filter(row=>row.complete).length}명</b><span>발송 가능한 기록 작성됨</span></div><div><small>{listMode==="ready"?"발송 선택":"발송 완료"}</small><b>{listMode==="ready"?checkedRows.length:sentRows.length}명</b><span>{listMode==="ready"?"체크한 학생만 발송":"현재 선택 기간 기준"}</span></div></div>
    {listMode==="ready"?<><div className={styles.layout}>
      <aside className={styles.students}><header><div><b>{type==="daily"?"오늘 작성 진행 현황":"이번 주 작성 진행 현황"}</b><small>예정 학생 전체 · 완료 학생 자동 선택</small></div><span>{readyStudents.length}명</span></header><div className={styles.selectAll}><label><input type="checkbox" checked={allSelected} onChange={()=>setChecked(allSelected?new Set():new Set(selectable.map(row=>row.studentId)))}/><span>완료 학생 전체 선택</span></label><em>{checkedRows.length}명 선택</em></div><div>{visibleStudents.map(item=>{const record=historyMap.get(item.studentId);const disabled=!item.recipient.available||record?.status==="sent"||item.completedCount===0;return <article key={item.studentId} className={`${selectedId===item.studentId?styles.selected:""} ${disabled?styles.disabled:""} ${!item.complete?styles.incomplete:""}`}><input aria-label={`${item.studentName} 발송 선택`} type="checkbox" checked={checked.has(item.studentId)&&!disabled} disabled={disabled} onChange={()=>toggle(item)}/><button onClick={()=>{setStudentId(item.studentId);setMessage("")}}><span><b>{item.studentName}</b><small>{item.school||"학교 미입력"} · {item.grade||"학년 미입력"} · 완료 {item.completedCount}/{item.expectedCount}</small></span><em className={record?.status==="sent"?styles.sent:record?.status==="failed"?styles.failed:item.complete?styles.sent:styles.warningBadge}>{record?.status==="sent"?"발송 완료":!item.recipient.available?"연락처 없음":item.completedCount===0?"기록 없음":record?.status==="failed"?"재발송 대기":item.complete?"준비 완료":`미작성 ${item.expectedCount-item.completedCount}건`}</em></button></article>})}{!visibleStudents.length&&<p>{loading?"예정 수업을 확인하고 있습니다…":"이 기간에 예정된 학생이 없습니다."}</p>}</div></aside>
      <main className={styles.workspace}>
        <header className={styles.selection}><div><small>{type==="daily"?"DAILY MESSAGE":"WEEKLY MESSAGE"}</small><h2>{student?.studentName??"예정 학생이 없습니다"}</h2><p>{formatPeriod(period.start,period.end)}</p></div><span className={styles.autoBadge}>작성된 내용 자동 생성</span></header>
        {!student&&!loading?<Empty text="이 기간에 예정된 수업이 있는 학생이 없습니다."/>:student?<>
          <div className={styles.readiness}><div><i className={student.complete?styles.ok:styles.warning}>!</i><span><b>{student.complete?"예정 기록 완료":"일부 기록 미작성"}</b><small>{student.completedCount}/{student.expectedCount}건 작성됨</small></span></div><div><i className={student.recipient.available?styles.ok:""}>✓</i><span><b>수신 학부모</b><small>{student.recipient.available?`${student.recipient.guardianName} · ${student.recipient.maskedPhone}`:"등록된 학부모 연락처 없음"}</small></span></div><div><i className={student.lessons.length?styles.ok:""}>✓</i><span><b>내용 자동 생성</b><small>{student.lessons.length?"수업·출결·시험·과제 요약 완료":"작성된 기록 없음"}</small></span></div></div>
          {!student.complete&&<section className={styles.missing}><header><b>아직 작성되지 않은 기록</b><span>{student.missingItems.length}건</span></header><div>{student.missingItems.map((item,index)=><p key={`${item.date}-${item.time}-${item.title}-${index}`}><strong>{formatDay(item.date)} {item.time}</strong><span>{item.kind} · {item.title}</span></p>)}</div><small>현재 발송하면 아래 미리보기에 포함된 작성 완료 기록만 전달됩니다.</small></section>}
          <section className={styles.preview}><div className={styles.kakaoHead}><span>한살매 수업노트</span><small>알림톡 도착 화면 미리보기</small></div><article><pre>{preview.body}</pre><button>학습기록 확인</button></article></section>
          <section className={styles.variables}><header><b>발송 변수 확인</b><span>내용이 없는 시험·과제 항목은 발송문에서 제외됩니다.</span></header><dl><div><dt>수업</dt><dd>{preview.lesson}</dd></div><div><dt>출결</dt><dd>{preview.attendance}</dd></div><div><dt>시험</dt><dd className={styles.multiline}>{preview.exam||"기록 없음 · 발송문에서 제외"}</dd></div><div><dt>과제</dt><dd className={styles.multiline}>{preview.homework||"기록 없음 · 발송문에서 제외"}</dd></div></dl></section>
          <footer className={styles.actions}><div>{message&&<p className={message.includes("접수")?styles.success:styles.error}>{message}</p>}{sentRecord?.status==="sent"&&<span>이 기간은 이미 발송되었습니다.</span>}</div><button className={styles.primary} onClick={sendCurrent} disabled={sending||!student.recipient.available||!student.lessons.length||sentRecord?.status==="sent"}>{sending?"발송 중…":sentRecord?.status==="sent"?"발송 완료":student.complete?"이 학생만 발송":"작성된 기록만 발송"}</button></footer>
        </>:<Empty text="완료 기록을 확인하고 있습니다…"/>}
      </main>
    </div>
    <div className={styles.bulkBar}><div><b>선택 학생 {checkedRows.length}명</b><span>완료 학생은 자동 선택되며, 미완료 학생은 직접 선택할 수 있습니다.</span></div><button disabled={!checkedRows.length||sending} onClick={()=>setConfirming(true)}>{sending?"일괄 발송 중…":`선택 ${checkedRows.length}명 일괄 발송`}</button></div></>:<section className={styles.sentPanel}><header><div><small>{type==="daily"?"DAILY HISTORY":"WEEKLY HISTORY"}</small><h2>{type==="daily"?"일간 발송 완료":"주간 발송 완료"}</h2><p>{formatPeriod(period.start,period.end)} · 성공적으로 발송된 학생만 표시됩니다.</p></div><span>{visibleSentRows.length}명</span></header><div className={styles.sentList}>{visibleSentRows.map(item=><article key={item.id}><i><HansalmaeIcon name="chat" size={18}/></i><div><b>{item.studentName}</b><span>{type==="daily"?"일간 학습기록":"주간 학습요약"}</span></div><time>{formatSentAt(item.sentAt)}</time><em>발송 완료</em></article>)}{!visibleSentRows.length&&<Empty text={loading?"발송 이력을 확인하고 있습니다…":"이 기간에 발송 완료된 학생이 없습니다."}/>}</div></section>}
    {confirming&&<div className={styles.confirmBackdrop} onMouseDown={event=>{if(event.target===event.currentTarget)setConfirming(false)}}><section className={styles.confirm} role="dialog" aria-modal="true"><i><HansalmaeIcon name="chat" size={25}/></i><h2>{checkedRows.length}명에게 알림톡을 발송할까요?</h2><p>{formatPeriod(period.start,period.end)}의 작성된 기록으로 자동 생성한 내용을 발송합니다.{checkedRows.some(row=>!row.complete)?" 미완료 학생은 현재까지 작성된 기록만 포함됩니다.":""} 이미 발송된 학생과 체크를 해제한 학생은 제외됩니다.</p><div><button className={styles.secondary} onClick={()=>setConfirming(false)}>취소</button><button className={styles.primary} onClick={()=>void sendSelected()}>확인 후 일괄 발송</button></div></section></div>}
    {incompletePrompt&&<div className={styles.confirmBackdrop} onMouseDown={event=>{if(event.target===event.currentTarget)setIncompletePrompt(null)}}><section className={`${styles.confirm} ${styles.warningConfirm}`} role="alertdialog" aria-modal="true"><i>!</i><h2>{incompletePrompt.row.studentName} 학생은 미작성 기록이 있습니다</h2><p>예정 {incompletePrompt.row.expectedCount}건 중 {incompletePrompt.row.completedCount}건만 작성됐습니다. 지금 진행하면 작성된 기록만 알림톡에 포함됩니다.</p><div><button className={styles.secondary} onClick={()=>setIncompletePrompt(null)}>돌아가기</button><button className={styles.primary} onClick={acceptIncomplete}>{incompletePrompt.action==="send"?"작성된 기록만 발송":"그래도 발송 선택"}</button></div></section></div>}
  </section>
}

function buildPreview(name:string,start:string,type:ReportType,lessons:Lesson[]):Preview{
  const counts=new Map<string,number>();for(const row of lessons){const key=row.source==="regular"?row.subject:`${row.subject} ${kindLabel[row.source]}`;counts.set(key,(counts.get(key)??0)+1)}
  const lesson=counts.size?Array.from(counts).map(([label,count])=>`${label}${count>1?` ${count}회`:""}`).join(" · "):"완료된 수업 없음";
  const statuses=lessons.map(row=>row.attendance?.status).filter(Boolean) as string[];const attendance=statuses.length?Array.from(new Set(statuses)).map(status=>`${attendanceLabel[status]??status} ${statuses.filter(value=>value===status).length}회`).join(" · "):"출결 기록 없음";
  const examItems=unique(lessons.flatMap(row=>{const scored=(row.exams??[]).filter(exam=>exam.score!==null).map(exam=>formatExam(row.subject,exam));return scored.length?scored:row.examContent?[`- ${row.subject}: ${short(row.examContent,42)}`]:[]}));
  const homeworkItems=groupBySubject(lessons.filter(row=>row.homeworkContent).map(row=>({subject:row.subject,value:cleanMultiline(row.homeworkContent)})));
  const exam=summarize(examItems,type==="weekly"?3:4);
  const homework=summarize(homeworkItems,type==="weekly"?3:4);
  const date=type==="daily"?formatDay(start):formatPeriod(...Object.values(periodFor(type,start)) as [string,string]);
  const learningDetails=buildLearningDetails(exam,homework);
  const body=`[한살매 수업노트]\n\n${name} 학생의 ${date} ${type==="daily"?"학습기록":"주간 학습요약"}입니다.\n\n■ 수업\n${lesson}\n\n■ 출결\n${attendance}\n\n■ 학습 상세\n${learningDetails}\n\n자세한 수업 내용과 선생님 피드백은\n아래 '학습기록 확인' 버튼에서 확인해 주세요.`;
  return{lesson,attendance,exam,homework,body};
}
function formatExam(subject:string,exam:Lesson["exams"][number]){
  const category=exam.examType.trim()||"시험";
  const title=exam.examTitle.trim();
  const maxScore=Number(exam.maxScore);
  const score=Number(exam.score);
  const wordUnit=category.replace(/\s+/g,"").includes("단어시험")?"개":"";
  const converted=Number.isFinite(score)&&Number.isFinite(maxScore)&&maxScore>0?` (${Math.round(score*100/maxScore)}점)`:"";
  return `- ${subject}: ${category}${title&&title!==category?`(${title})`:""} ${score}/${maxScore}${wordUnit}${converted}`;
}
function groupBySubject(items:{subject:string;value:string}[]){
  const grouped=new Map<string,string[]>();
  for(const item of items){const values=grouped.get(item.subject)??[];if(!values.includes(item.value))values.push(item.value);grouped.set(item.subject,values)}
  return Array.from(grouped,([subject,values])=>values.flatMap(value=>value.split("\n")).map((line,index)=>index===0?`- ${subject}: ${line}`:`　　　 ${line}`).join("\n"));
}
function short(value:string,max:number){const clean=value.replace(/\s+/g," ").trim();return clean.length>max?`${clean.slice(0,max-1)}…`:clean}
function cleanMultiline(value:string){return value.split(/\r?\n/).map(line=>line.trim()).filter(Boolean).join("\n")}
function unique(values:string[]){return Array.from(new Set(values.map(value=>value.trim()).filter(Boolean)))}
function summarize(values:string[],limit:number){if(!values.length)return"";const shown=values.slice(0,limit);return `${shown.join("\n")}${values.length>limit?`\n외 ${values.length-limit}건`:""}`}
function buildLearningDetails(exam:string,homework:string){return [formatDetailGroup("시험",exam),formatDetailGroup("과제",homework)].filter(Boolean).join("\n\n")||"수업 기록 완료"}
function formatDetailGroup(label:string,value:string){return value?`<${label}>\n${value}`:""}
function today(){return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date())}
function periodFor(type:ReportType,anchor:string){if(type==="daily")return{start:anchor,end:anchor};const date=new Date(`${anchor}T12:00:00+09:00`);const day=(date.getDay()+6)%7;date.setDate(date.getDate()-day);const start=todayFrom(date);date.setDate(date.getDate()+6);return{start,end:todayFrom(date)}}
function todayFrom(date:Date){return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(date)}
function formatDay(value:string){const[,month,day]=value.split("-").map(Number);return `${month}월 ${day}일`}
function formatPeriod(start:string,end:string){return start===end?formatDay(start):`${formatDay(start)}~${formatDay(end)}`}
function formatSentAt(value:string|null){if(!value)return"발송 시각 확인 중";return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"long",day:"numeric",hour:"2-digit",minute:"2-digit",hour12:false}).format(new Date(value))}
function Empty({text}:{text:string}){return <div className={styles.empty}><HansalmaeIcon name="chat" size={25}/><b>{text}</b><span>완료된 정규·보강·추가·첨삭 기록만 반영됩니다.</span></div>}
