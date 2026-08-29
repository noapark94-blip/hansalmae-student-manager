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

const kindLabel={regular:"정규",makeup:"보강",extra:"추가",correction:"첨삭"};
const attendanceLabel:Record<string,string>={present:"출석",late:"지각",absent:"결석",excused:"인정결석",scheduled:"예정"};

export function AlimtalkSendCenter({supabase,students}:{supabase:SupabaseClient;students:StudentRow[]}){
  const [type,setType]=useState<ReportType>("daily");
  const [anchor,setAnchor]=useState(today());
  const [query,setQuery]=useState("");
  const [studentId,setStudentId]=useState("");
  const [lessons,setLessons]=useState<Lesson[]>([]);
  const [recipient,setRecipient]=useState<Recipient|null>(null);
  const [history,setHistory]=useState<History[]>([]);
  const [loading,setLoading]=useState(false);
  const [sending,setSending]=useState(false);
  const [message,setMessage]=useState("");
  const period=useMemo(()=>periodFor(type,anchor),[type,anchor]);
  const activeStudents=useMemo(()=>students.filter(student=>(student.status==="active"||student.status==="재원")&&(!query.trim()||[student.name,student.school??"",student.grade??"",...student.enrollments.flatMap(item=>[item.classes?.name??"",item.classes?.subject??""])].some(value=>value.toLowerCase().includes(query.trim().toLowerCase())))).sort((a,b)=>a.name.localeCompare(b.name,"ko")),[query,students]);
  const selectedId=activeStudents.some(student=>student.id===studentId)?studentId:activeStudents[0]?.id??"";
  const student=students.find(item=>item.id===selectedId);
  const historyMap=useMemo(()=>new Map(history.filter(item=>item.reportType===type&&item.periodStart===period.start).map(item=>[item.studentId,item])),[history,period.start,type]);
  const preview=useMemo(()=>buildPreview(student?.name??"학생",period.start,type,lessons),[lessons,period.start,student?.name,type]);
  const sentRecord=historyMap.get(selectedId);

  const loadHistory=useCallback(async()=>{const{data}=await supabase.rpc("staff_alimtalk_delivery_list");setHistory((data??[]) as History[])},[supabase]);
  useEffect(()=>{let active=true;void supabase.rpc("staff_alimtalk_delivery_list").then(({data})=>{if(active)setHistory((data??[]) as History[])});return()=>{active=false}},[supabase]);

  async function loadPreview(){
    if(!selectedId)return;setLoading(true);setMessage("");setLessons([]);setRecipient(null);
    const[source,target]=await Promise.all([
      supabase.rpc("staff_learning_report_source",{p_student_id:selectedId,p_from:period.start,p_to:period.end}),
      supabase.rpc("staff_alimtalk_recipient",{p_student_id:selectedId}),
    ]);
    if(source.error)setMessage(source.error.message);else setLessons((source.data??[]) as Lesson[]);
    if(target.error)setMessage(current=>current||target.error.message);else setRecipient(target.data as Recipient);
    setLoading(false);
  }

  async function send(){
    if(!student||!recipient?.available||!lessons.length)return;setSending(true);setMessage("");
    const{data,error}=await supabase.functions.invoke("send-learning-alimtalk",{body:{studentId:student.id,reportType:type,periodStart:period.start,periodEnd:period.end,lessonSummary:preview.lesson,attendanceSummary:preview.attendance,learningSummary:preview.learning}});
    if(error){let text=error.message;const context=(error as{context?:Response}).context;if(context)try{const body=await context.clone().json() as{error?:string};if(body.error)text=body.error}catch{}setMessage(text)}else{const result=data as{sent?:number};setMessage(`${student.name} 학생 학부모님께 알림톡 ${result.sent??1}건을 접수했습니다.`);await loadHistory()}
    setSending(false);
  }

  return <section className={styles.center}>
    <header className={styles.hero}><div><p>학부모 소통</p><h1>알림톡 발송</h1><span>완료된 학습기록을 짧게 정리해 발송 전 확인합니다.</span></div><i><HansalmaeIcon name="chat" size={27}/></i></header>
    <nav className={styles.tabs}><button className={type==="daily"?styles.active:""} onClick={()=>{setType("daily");setLessons([]);setRecipient(null)}}>일간 기록 발송</button><button className={type==="weekly"?styles.active:""} onClick={()=>{setType("weekly");setLessons([]);setRecipient(null)}}>주간 기록 발송</button></nav>
    <div className={styles.toolbar}><label><span>{type==="daily"?"기록 날짜":"주간 기준일"}</span><input type="date" value={anchor} onChange={event=>{setAnchor(event.target.value);setLessons([]);setRecipient(null)}}/></label><label className={styles.search}><span>학생 검색</span><i><HansalmaeIcon name="students" size={16}/><input value={query} onChange={event=>{setQuery(event.target.value);setStudentId("");setLessons([])}} placeholder="이름·학교·클래스 검색"/></i></label><div className={styles.period}><small>발송 기준</small><b>{formatPeriod(period.start,period.end)}</b></div><button className={styles.refresh} onClick={()=>void loadHistory()}><HansalmaeIcon name="refresh" size={15}/> 발송내역 새로고침</button></div>
    <div className={styles.layout}>
      <aside className={styles.students}><header><b>학생별 발송 준비</b><span>{activeStudents.length}명</span></header><div>{activeStudents.map(item=>{const record=historyMap.get(item.id);return <button key={item.id} className={selectedId===item.id?styles.selected:""} onClick={()=>{setStudentId(item.id);setLessons([]);setRecipient(null);setMessage("")}}><span><b>{item.name}</b><small>{item.school??"학교 미입력"} · {item.grade??"학년 미입력"}</small></span><em className={record?.status==="sent"?styles.sent:record?.status==="failed"?styles.failed:""}>{record?.status==="sent"?"발송 완료":record?.status==="failed"?"발송 실패":"미리보기"}</em></button>})}{!activeStudents.length&&<p>검색된 학생이 없습니다.</p>}</div></aside>
      <main className={styles.workspace}>
        <header className={styles.selection}><div><small>{type==="daily"?"DAILY MESSAGE":"WEEKLY MESSAGE"}</small><h2>{student?.name??"학생을 선택해 주세요"}</h2><p>{formatPeriod(period.start,period.end)}</p></div><button onClick={()=>void loadPreview()} disabled={!selectedId||loading}>{loading?"기록 불러오는 중…":"발송 내용 만들기"}</button></header>
        {!lessons.length&&!loading?<Empty text="학생과 날짜를 선택한 뒤 ‘발송 내용 만들기’를 눌러주세요."/>:<>
          <div className={styles.readiness}><div><i className={lessons.length?styles.ok:""}>✓</i><span><b>학습기록</b><small>{lessons.length?`${lessons.length}건 반영됨`:"완료된 기록 없음"}</small></span></div><div><i className={recipient?.available?styles.ok:""}>✓</i><span><b>수신 학부모</b><small>{recipient?.available?`${recipient.guardianName} · ${recipient.maskedPhone}`:"등록된 학부모 연락처 없음"}</small></span></div><div><i className={preview.learning.length<=180?styles.ok:""}>✓</i><span><b>내용 길이</b><small>학습요약 {preview.learning.length}/180자</small></span></div></div>
          <section className={styles.preview}><div className={styles.kakaoHead}><span>한살매 수업노트</span><small>알림톡 도착 화면 미리보기</small></div><article><pre>{preview.body}</pre><button>학습기록 확인</button></article></section>
          <section className={styles.variables}><header><b>발송 변수 확인</b><span>승인 템플릿의 고정 문구는 수정하지 않습니다.</span></header><dl><div><dt>수업요약</dt><dd>{preview.lesson}</dd></div><div><dt>출결요약</dt><dd>{preview.attendance}</dd></div><div><dt>학습요약</dt><dd className={styles.multiline}>{preview.learning}</dd></div></dl></section>
          <footer className={styles.actions}><div>{message&&<p className={message.includes("접수")?styles.success:styles.error}>{message}</p>}{sentRecord?.status==="sent"&&<span>이 기간은 이미 발송되었습니다. 재발송하려면 발송내역에서 별도로 확인해야 합니다.</span>}</div><button className={styles.secondary} onClick={()=>void loadPreview()}>내용 다시 만들기</button><button className={styles.primary} onClick={()=>void send()} disabled={sending||!recipient?.available||!lessons.length||sentRecord?.status==="sent"}>{sending?"발송 중…":sentRecord?.status==="sent"?"발송 완료":"확인 후 알림톡 발송"}</button></footer>
        </>}
      </main>
    </div>
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
