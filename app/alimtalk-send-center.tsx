"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { StudentRow } from "./supabase";
import { HansalmaeIcon } from "./hansalmae-icons";
import styles from "./alimtalk-send-center.module.css";

type ReportType="daily"|"weekly";
type Lesson={lessonId:string;lessonDate:string;className:string;subject:string;source:"regular"|"makeup"|"extra"|"correction";lessonContent:string;homeworkContent:string;examContent:string;attendance:{status:string;lateMinutes:number|null}|null;exams:{examTitle:string;score:number|null;maxScore:number}[]};
type Recipient={guardianName:string;maskedPhone:string;available:boolean};
type History={id:string;studentId:string;studentName:string;reportType:ReportType;periodStart:string;status:string;sentAt:string|null;errorMessage:string|null};
type Preview={lesson:string;attendance:string;learning:string;body:string};
type ReadyStudent={studentId:string;studentName:string;school:string;grade:string;expectedCount:number;completedCount:number;lessons:Lesson[];recipient:Recipient};

const kindLabel={regular:"정규",makeup:"보강",extra:"추가",correction:"첨삭"};
const attendanceLabel:Record<string,string>={present:"출석",late:"지각",absent:"결석",excused:"인정결석",scheduled:"예정"};

export function AlimtalkSendCenter({supabase}:{supabase:SupabaseClient;students:StudentRow[]}){
  const [type,setType]=useState<ReportType>("daily");
  const [anchor,setAnchor]=useState(today());
  const [query,setQuery]=useState("");
  const [studentId,setStudentId]=useState("");
  const [readyStudents,setReadyStudents]=useState<ReadyStudent[]>([]);
  const [checked,setChecked]=useState<Set<string>>(new Set());
  const [history,setHistory]=useState<History[]>([]);
  const [loading,setLoading]=useState(true);
  const [sending,setSending]=useState(false);
  const [confirming,setConfirming]=useState(false);
  const [message,setMessage]=useState("");
  const period=useMemo(()=>periodFor(type,anchor),[type,anchor]);
  const historyMap=useMemo(()=>new Map(history.filter(item=>item.reportType===type&&item.periodStart===period.start).map(item=>[item.studentId,item])),[history,period.start,type]);
  const visibleStudents=useMemo(()=>readyStudents.filter(item=>!query.trim()||[item.studentName,item.school,item.grade].some(value=>value.toLowerCase().includes(query.trim().toLowerCase()))),[query,readyStudents]);
  const selectedId=readyStudents.some(item=>item.studentId===studentId)?studentId:readyStudents[0]?.studentId??"";
  const student=readyStudents.find(item=>item.studentId===selectedId);
  const preview=useMemo(()=>buildPreview(student?.studentName??"학생",period.start,type,student?.lessons??[]),[period.start,student,type]);
  const sentRecord=historyMap.get(selectedId);
  const checkedRows=readyStudents.filter(item=>checked.has(item.studentId)&&historyMap.get(item.studentId)?.status!=="sent"&&item.recipient.available);

  const loadHistory=useCallback(async()=>{const{data}=await supabase.rpc("staff_alimtalk_delivery_list");setHistory((data??[]) as History[])},[supabase]);
  useEffect(()=>{let active=true;void supabase.rpc("staff_alimtalk_delivery_list").then(({data})=>{if(active)setHistory((data??[]) as History[])});return()=>{active=false}},[supabase]);
  const loadReady=useCallback(async()=>{setLoading(true);setMessage("");const{data,error}=await supabase.rpc("staff_alimtalk_ready_students",{p_from:period.start,p_to:period.end});if(error){setReadyStudents([]);setChecked(new Set());setMessage(error.message)}else{const rows=(data??[]) as ReadyStudent[];setReadyStudents(rows);setStudentId(current=>rows.some(row=>row.studentId===current)?current:rows[0]?.studentId??"");setChecked(new Set(rows.filter(row=>row.recipient.available).map(row=>row.studentId)))}setLoading(false)},[period.end,period.start,supabase]);
  useEffect(()=>{let active=true;void supabase.rpc("staff_alimtalk_ready_students",{p_from:period.start,p_to:period.end}).then(({data,error})=>{if(!active)return;if(error){setReadyStudents([]);setChecked(new Set());setMessage(error.message);setLoading(false);return}const rows=(data??[]) as ReadyStudent[];setReadyStudents(rows);setStudentId(rows[0]?.studentId??"");setChecked(new Set(rows.filter(row=>row.recipient.available).map(row=>row.studentId)));setLoading(false)});return()=>{active=false}},[period.end,period.start,supabase]);

  async function sendRow(row:ReadyStudent){const itemPreview=buildPreview(row.studentName,period.start,type,row.lessons);const{error}=await supabase.functions.invoke("send-learning-alimtalk",{body:{studentId:row.studentId,reportType:type,periodStart:period.start,periodEnd:period.end,lessonSummary:itemPreview.lesson,attendanceSummary:itemPreview.attendance,learningSummary:itemPreview.learning}});if(!error)return null;let text=error.message;const context=(error as{context?:Response}).context;if(context)try{const body=await context.clone().json() as{error?:string};if(body.error)text=body.error}catch{}return text}
  async function sendSelected(){if(!checkedRows.length)return;setSending(true);setConfirming(false);setMessage("");let sent=0;const failed:string[]=[];for(let index=0;index<checkedRows.length;index+=3){const batch=checkedRows.slice(index,index+3);const results=await Promise.all(batch.map(async row=>({row,error:await sendRow(row)})));for(const result of results){if(result.error)failed.push(`${result.row.studentName}: ${result.error}`);else sent+=1}}await loadHistory();setChecked(new Set(failed.map(line=>readyStudents.find(row=>line.startsWith(`${row.studentName}:`))?.studentId).filter(Boolean) as string[]));setMessage(failed.length?`${sent}명 발송 접수 · ${failed.length}명 실패 (${failed.slice(0,2).join(" / ")})`:`${sent}명 학부모님께 알림톡 발송을 접수했습니다.`);setSending(false)}
  async function sendCurrent(){if(!student)return;setSending(true);setMessage("");const error=await sendRow(student);if(error)setMessage(error);else{setMessage(`${student.studentName} 학생 학부모님께 알림톡을 접수했습니다.`);await loadHistory()}setSending(false)}
  function resetPeriod(nextType?:ReportType,nextAnchor?:string){if(nextType)setType(nextType);if(nextAnchor)setAnchor(nextAnchor);setLoading(true);setReadyStudents([]);setChecked(new Set());setStudentId("");setMessage("")}
  function toggle(id:string){setChecked(current=>{const next=new Set(current);if(next.has(id))next.delete(id);else next.add(id);return next})}
  const selectable=readyStudents.filter(row=>row.recipient.available&&historyMap.get(row.studentId)?.status!=="sent");
  const allSelected=selectable.length>0&&selectable.every(row=>checked.has(row.studentId));

  return <section className={styles.center}>
    <header className={styles.hero}><div><p>학부모 소통</p><h1>알림톡 발송</h1><span>완료된 학습기록을 짧게 정리해 발송 전 확인합니다.</span></div><i><HansalmaeIcon name="chat" size={27}/></i></header>
    <nav className={styles.tabs}><button className={type==="daily"?styles.active:""} onClick={()=>resetPeriod("daily")}>일간 기록 발송</button><button className={type==="weekly"?styles.active:""} onClick={()=>resetPeriod("weekly")}>주간 기록 발송</button></nav>
    <div className={styles.toolbar}><label><span>{type==="daily"?"기록 날짜":"주간 기준일"}</span><input type="date" value={anchor} onChange={event=>resetPeriod(undefined,event.target.value)}/></label><label className={styles.search}><span>준비 학생 검색</span><i><HansalmaeIcon name="students" size={16}/><input value={query} onChange={event=>setQuery(event.target.value)} placeholder="이름·학교 검색"/></i></label><div className={styles.period}><small>발송 기준</small><b>{formatPeriod(period.start,period.end)}</b></div><button className={styles.refresh} onClick={()=>void Promise.all([loadReady(),loadHistory()])}><HansalmaeIcon name="refresh" size={15}/> 대상·내역 새로고침</button></div>
    <div className={styles.summary}><div><small>기록 완료</small><b>{readyStudents.length}명</b><span>예정 기록이 모두 작성됨</span></div><div><small>발송 선택</small><b>{checkedRows.length}명</b><span>체크한 학생만 발송</span></div><div><small>발송 완료</small><b>{readyStudents.filter(row=>historyMap.get(row.studentId)?.status==="sent").length}명</b><span>현재 발송 기간 기준</span></div></div>
    <div className={styles.layout}>
      <aside className={styles.students}><header><div><b>자동 발송 준비</b><small>모든 예정 기록이 끝난 학생</small></div><span>{readyStudents.length}명</span></header><div className={styles.selectAll}><label><input type="checkbox" checked={allSelected} onChange={()=>setChecked(allSelected?new Set():new Set(selectable.map(row=>row.studentId)))}/><span>발송 가능 학생 전체 선택</span></label><em>{checkedRows.length}명 선택</em></div><div>{visibleStudents.map(item=>{const record=historyMap.get(item.studentId);const disabled=!item.recipient.available||record?.status==="sent";return <article key={item.studentId} className={`${selectedId===item.studentId?styles.selected:""} ${disabled?styles.disabled:""}`}><input aria-label={`${item.studentName} 발송 선택`} type="checkbox" checked={checked.has(item.studentId)&&!disabled} disabled={disabled} onChange={()=>toggle(item.studentId)}/><button onClick={()=>{setStudentId(item.studentId);setMessage("")}}><span><b>{item.studentName}</b><small>{item.school||"학교 미입력"} · {item.grade||"학년 미입력"} · {item.completedCount}건 완료</small></span><em className={record?.status==="sent"?styles.sent:record?.status==="failed"?styles.failed:""}>{record?.status==="sent"?"발송 완료":!item.recipient.available?"연락처 없음":record?.status==="failed"?"재발송 대기":"준비 완료"}</em></button></article>})}{!visibleStudents.length&&<p>{loading?"완료 기록을 확인하고 있습니다…":"이 기간에 발송 준비가 끝난 학생이 없습니다."}</p>}</div></aside>
      <main className={styles.workspace}>
        <header className={styles.selection}><div><small>{type==="daily"?"DAILY MESSAGE":"WEEKLY MESSAGE"}</small><h2>{student?.studentName??"발송 준비 학생이 없습니다"}</h2><p>{formatPeriod(period.start,period.end)}</p></div><span className={styles.autoBadge}>내용 자동 생성</span></header>
        {!student&&!loading?<Empty text="예정된 수업 기록이 모두 작성되면 학생이 자동으로 나타납니다."/>:student?<>
          <div className={styles.readiness}><div><i className={styles.ok}>✓</i><span><b>예정 기록 완료</b><small>{student.completedCount}/{student.expectedCount}건 작성됨</small></span></div><div><i className={student.recipient.available?styles.ok:""}>✓</i><span><b>수신 학부모</b><small>{student.recipient.available?`${student.recipient.guardianName} · ${student.recipient.maskedPhone}`:"등록된 학부모 연락처 없음"}</small></span></div><div><i className={preview.learning.length<=180?styles.ok:""}>✓</i><span><b>내용 자동 생성</b><small>학습요약 {preview.learning.length}/180자</small></span></div></div>
          <section className={styles.preview}><div className={styles.kakaoHead}><span>한살매 수업노트</span><small>알림톡 도착 화면 미리보기</small></div><article><pre>{preview.body}</pre><button>학습기록 확인</button></article></section>
          <section className={styles.variables}><header><b>발송 변수 확인</b><span>승인 템플릿의 고정 문구는 수정하지 않습니다.</span></header><dl><div><dt>수업요약</dt><dd>{preview.lesson}</dd></div><div><dt>출결요약</dt><dd>{preview.attendance}</dd></div><div><dt>학습요약</dt><dd className={styles.multiline}>{preview.learning}</dd></div></dl></section>
          <footer className={styles.actions}><div>{message&&<p className={message.includes("접수")?styles.success:styles.error}>{message}</p>}{sentRecord?.status==="sent"&&<span>이 기간은 이미 발송되었습니다.</span>}</div><button className={styles.primary} onClick={()=>void sendCurrent()} disabled={sending||!student.recipient.available||!student.lessons.length||sentRecord?.status==="sent"}>{sending?"발송 중…":sentRecord?.status==="sent"?"발송 완료":"이 학생만 발송"}</button></footer>
        </>:<Empty text="완료 기록을 확인하고 있습니다…"/>}
      </main>
    </div>
    <div className={styles.bulkBar}><div><b>{type==="daily"?"하루 일과 완료 학생":"주간 기록 완료 학생"} {checkedRows.length}명</b><span>체크를 해제한 학생은 이번 발송에서 제외됩니다.</span></div><button disabled={!checkedRows.length||sending} onClick={()=>setConfirming(true)}>{sending?"일괄 발송 중…":`선택 ${checkedRows.length}명 일괄 발송`}</button></div>
    {confirming&&<div className={styles.confirmBackdrop} onMouseDown={event=>{if(event.target===event.currentTarget)setConfirming(false)}}><section className={styles.confirm} role="dialog" aria-modal="true"><i><HansalmaeIcon name="chat" size={25}/></i><h2>{checkedRows.length}명에게 알림톡을 발송할까요?</h2><p>{formatPeriod(period.start,period.end)}의 완료 기록으로 자동 생성된 내용을 발송합니다. 이미 발송된 학생과 체크를 해제한 학생은 제외됩니다.</p><div><button className={styles.secondary} onClick={()=>setConfirming(false)}>취소</button><button className={styles.primary} onClick={()=>void sendSelected()}>확인 후 일괄 발송</button></div></section></div>}
  </section>
}

function buildPreview(name:string,start:string,type:ReportType,lessons:Lesson[]):Preview{
  const counts=new Map<string,number>();for(const row of lessons){const key=`${row.subject} ${kindLabel[row.source]}`;counts.set(key,(counts.get(key)??0)+1)}
  const lesson=counts.size?Array.from(counts).map(([label,count])=>`${label}${count>1?` ${count}회`:""}`).join(" · "):"완료된 수업 없음";
  const statuses=lessons.map(row=>row.attendance?.status).filter(Boolean) as string[];const attendance=statuses.length&&new Set(statuses).size===1&&statuses[0]==="present"?"전체 출석":statuses.length?Array.from(new Set(statuses)).map(status=>`${attendanceLabel[status]??status} ${statuses.filter(value=>value===status).length}회`).join(" · "):"출결 기록 없음";
  const groups=new Map<string,Lesson[]>();for(const row of lessons){const list=groups.get(row.subject)??[];list.push(row);groups.set(row.subject,list)}
  const lines=Array.from(groups).slice(0,4).map(([subject,rows])=>{const details:string[]=[];const content=first(rows.map(row=>row.lessonContent).filter(Boolean));if(content)details.push(short(content,38));const exams=rows.flatMap(row=>row.exams??[]).filter(exam=>exam.score!==null).slice(0,2).map(exam=>`${exam.examTitle||"시험"} ${exam.score}/${exam.maxScore}`);details.push(...exams);const homework=first(rows.map(row=>row.homeworkContent).filter(Boolean));if(homework)details.push(`과제 ${short(homework,28)}`);return `${subject}｜${details.length?details.join(" · "):"학습기록 완료"}`});
  if(groups.size>4)lines.push(`외 ${groups.size-4}개 과목`);const learning=short(lines.join("\n"),180);
  const date=type==="daily"?formatDay(start):formatPeriod(...Object.values(periodFor(type,start)) as [string,string]);
  const body=`[한살매 수업노트]\n\n${name} 학생의 ${date} ${type==="daily"?"학습기록":"주간 학습요약"}입니다.\n\n수업: ${lesson}\n출결: ${attendance}\n학습: ${learning}\n\n자세한 수업 내용과 선생님 피드백은 한살매 수업노트에서 확인해 주세요.`;
  return{lesson,attendance,learning,body};
}
function first(values:string[]){return values.find(value=>value.trim())?.trim()??""}
function short(value:string,max:number){const clean=value.replace(/\s+/g," ").trim();return clean.length>max?`${clean.slice(0,max-1)}…`:clean}
function today(){return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date())}
function periodFor(type:ReportType,anchor:string){if(type==="daily")return{start:anchor,end:anchor};const date=new Date(`${anchor}T12:00:00+09:00`);const day=(date.getDay()+6)%7;date.setDate(date.getDate()-day);const start=todayFrom(date);date.setDate(date.getDate()+6);return{start,end:todayFrom(date)}}
function todayFrom(date:Date){return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(date)}
function formatDay(value:string){const[,month,day]=value.split("-").map(Number);return `${month}월 ${day}일`}
function formatPeriod(start:string,end:string){return start===end?formatDay(start):`${formatDay(start)}~${formatDay(end)}`}
function Empty({text}:{text:string}){return <div className={styles.empty}><HansalmaeIcon name="chat" size={25}/><b>{text}</b><span>완료된 정규·보강·추가·첨삭 기록만 반영됩니다.</span></div>}
