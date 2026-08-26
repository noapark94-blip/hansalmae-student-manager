"use client";

import { useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { HansalmaeIcon } from "./hansalmae-icons";

type AttendanceInfo={status:string;lateMinutes:number|null;absenceReason:string;note:string}|null;
type HomeworkResult={status:string;note:string}|null;
type Exam={id:string;examType:string;examTitle:string;score:number|null;maxScore:number;percent:number|null;evaluation:string;feedback:string};
type Report={lessonId:string;lessonDate:string;startsAt:string;classId:string;className:string;subject:string;room:string|null;teacherName:string;lessonContent:string;homeworkContent:string;examContent:string;attendance:AttendanceInfo;homeworkResult:HomeworkResult;exams:Exam[]};
type ReadReceipt={lessonId:string;viewedAt:string};

const attendanceLabel:Record<string,string>={present:"출석",late:"지각",absent:"결석",excused:"결석"};
const homeworkLabel:Record<string,string>={complete:"완료",partial:"일부 완료",missing:"미제출",excused:"확인 제외"};

export function FamilyLearningReportFeed({supabase,studentId}:{supabase:SupabaseClient;studentId:string}){
  const [items,setItems]=useState<Report[]>([]);
  const [reads,setReads]=useState<Record<string,string>>({});
  const [subject,setSubject]=useState("전체");
  const [loading,setLoading]=useState(true);
  const [unavailable,setUnavailable]=useState(false);
  const [readTracking,setReadTracking]=useState(false);
  const [confirming,setConfirming]=useState<string|null>(null);
  const [selected,setSelected]=useState<Report|null>(null);

  useEffect(()=>{
    let active=true;
    void Promise.resolve().then(async()=>{
      if(!active)return;
      setLoading(true);setUnavailable(false);setReadTracking(false);setReads({});setSelected(null);
      const reportResult=await supabase.rpc("family_completed_learning_reports",{p_student_id:studentId,p_limit:20});
      if(!active)return;
      if(reportResult.error){setUnavailable(true);setItems([]);setLoading(false);return;}
      setItems((reportResult.data??[]) as Report[]);
      const readResult=await supabase.rpc("family_learning_report_reads",{p_student_id:studentId});
      if(!active)return;
      if(!readResult.error){
        const next:Record<string,string>={};
        for(const receipt of (readResult.data??[]) as ReadReceipt[])next[receipt.lessonId]=receipt.viewedAt;
        setReads(next);setReadTracking(true);
      }
      setLoading(false);
    })();
    return()=>{active=false};
  },[studentId,supabase]);

  useEffect(()=>{
    if(!selected)return;
    const close=(event:KeyboardEvent)=>{if(event.key==="Escape")setSelected(null)};
    document.addEventListener("keydown",close);
    return()=>document.removeEventListener("keydown",close);
  },[selected]);

  const subjects=useMemo(()=>Array.from(new Set(items.map(item=>item.subject).filter(Boolean))),[items]);
  const selectedSubject=subject==="전체"||subjects.includes(subject)?subject:"전체";
  const visibleItems=useMemo(()=>selectedSubject==="전체"?items:items.filter(item=>item.subject===selectedSubject),[items,selectedSubject]);
  const groups=useMemo(()=>{
    const grouped=new Map<string,Report[]>();
    for(const item of visibleItems){const current=grouped.get(item.lessonDate)??[];current.push(item);grouped.set(item.lessonDate,current);}
    return Array.from(grouped.entries());
  },[visibleItems]);
  const unreadCount=readTracking?items.filter(item=>!reads[item.lessonId]).length:0;

  async function confirmRead(lessonId:string){
    if(!readTracking||reads[lessonId]||confirming)return;
    setConfirming(lessonId);
    const {data,error}=await supabase.rpc("mark_family_learning_report_read",{p_student_id:studentId,p_lesson_id:lessonId});
    if(!error)setReads(current=>({...current,[lessonId]:String(data??new Date().toISOString())}));
    setConfirming(null);
  }

  if(unavailable)return null;
  return <section className="family-report-feed" aria-label="수업 학습 리포트">
    <header className="family-report-feed-title">
      <div><p className="eyebrow">하루하루 쌓이는 기록</p><h2>학습 피드</h2><span>오늘 무엇을 배우고 어떻게 해냈는지 확인하세요.</span></div>
      {readTracking&&unreadCount>0&&<strong className="family-report-unread-count">새 기록 {unreadCount}</strong>}
    </header>
    {subjects.length>1&&<nav className="family-report-subject-filter" aria-label="과목 필터"><button type="button" className={selectedSubject==="전체"?"active":""} onClick={()=>setSubject("전체")}>전체</button>{subjects.map(name=><button type="button" key={name} className={selectedSubject===name?"active":""} onClick={()=>setSubject(name)}>{name}</button>)}</nav>}
    {loading?<p className="family-report-empty">학습 기록을 불러오는 중이에요…</p>:!items.length?<p className="family-report-empty">아직 도착한 학습 기록이 없습니다.</p>:<div className="family-report-date-list">{groups.map(([date,reports])=><section className="family-report-date-group" key={date}><header><div><time>{formatDateTitle(date)}</time><span>{formatDateWeekday(date)}</span></div><small>{reports.length}개 수업</small></header><div className="family-report-list">{reports.map(item=><ReportCard key={item.lessonId} item={item} readAt={reads[item.lessonId]??null} readTracking={readTracking} onOpen={()=>setSelected(item)}/>)}</div></section>)}</div>}
    {selected&&<ReportDetail item={selected} readAt={reads[selected.lessonId]??null} readTracking={readTracking} confirming={confirming===selected.lessonId} onClose={()=>setSelected(null)} onConfirm={()=>void confirmRead(selected.lessonId)}/>}
  </section>;
}

function ReportCard({item,readAt,readTracking,onOpen}:{item:Report;readAt:string|null;readTracking:boolean;onOpen:()=>void}){
  const attendance=item.attendance;
  const firstExam=item.exams[0]??null;
  const preview=item.lessonContent||item.examContent||item.homeworkContent||firstExam?.evaluation||"수업 기록이 도착했어요.";
  return <article className={`family-report-card ${readTracking&&!readAt?"unread":""}`}>
    <button type="button" className="family-report-card-main" onClick={onOpen} aria-label={`${item.className} 리포트 자세히 보기`}>
      <span className="family-report-subject-mark" aria-hidden="true">{item.subject?.slice(0,1)||"수"}</span>
      <span className="family-report-subject">
        <span className="family-report-card-labels"><span>{item.subject}</span>{readTracking&&!readAt&&<em>NEW</em>}</span>
        <strong>{item.className}</strong>
        <small>{formatTime(item.startsAt)} · {item.teacherName}{item.room?` · ${item.room}`:""}</small>
        <p>{preview}</p>
        <span className="family-report-card-meta">{firstExam&&<em>{firstExam.score===null?(firstExam.examTitle||"시험 평가"):`${firstExam.examTitle||"시험"} ${formatScore(firstExam.score)}/${formatScore(firstExam.maxScore)}`}</em>}{item.homeworkResult&&<em>숙제 {homeworkLabel[item.homeworkResult.status]??item.homeworkResult.status}</em>}</span>
      </span>
      {attendance&&<strong className={`family-attendance-badge ${attendance.status}`}>{attendanceLabel[attendance.status]??attendance.status}{attendance.status==="late"&&attendance.lateMinutes?` ${attendance.lateMinutes}분`:""}</strong>}
      <span className="family-report-open">자세히 보기 <b>›</b></span>
    </button>
  </article>;
}

function ReportDetail({item,readAt,readTracking,confirming,onClose,onConfirm}:{item:Report;readAt:string|null;readTracking:boolean;confirming:boolean;onClose:()=>void;onConfirm:()=>void}){
  const attendance=item.attendance;
  const attendanceMemo=[attendance?.absenceReason,attendance?.note].filter(Boolean).join(" · ");
  const teacherFeedbacks=item.exams.filter(exam=>exam.feedback.trim()).map(exam=>({label:exam.examTitle||exam.examType||"시험",text:exam.feedback.trim()}));
  return <div className="family-report-detail-backdrop" onMouseDown={event=>{if(event.target===event.currentTarget)onClose()}}>
    <section className="family-report-detail" role="dialog" aria-modal="true" aria-labelledby="family-report-detail-title">
      <header className="family-report-detail-head"><button type="button" onClick={onClose} aria-label="상세 리포트 닫기">‹</button><div><small>{formatFullDate(item.lessonDate)}</small><h2 id="family-report-detail-title">수업 상세 리포트</h2></div><span/></header>
      <div className="family-report-detail-scroll">
        <section className="family-report-detail-hero"><div className="family-report-card-labels"><span>{item.subject}</span></div><div><h3>{item.className}</h3>{attendance&&<strong className={`family-attendance-badge ${attendance.status}`}>{attendanceLabel[attendance.status]??attendance.status}{attendance.status==="late"&&attendance.lateMinutes?` ${attendance.lateMinutes}분`:""}</strong>}</div><p>{formatTime(item.startsAt)} · {item.teacherName}{item.room?` · ${item.room}`:""}</p></section>
        <div className="family-report-detail-sections">
          {item.lessonContent&&<ReportSection icon="book" title="오늘 수업" text={item.lessonContent}/>}
          {item.examContent&&<ReportSection icon="chart" title="오늘 시험·평가" text={item.examContent}/>}
          {item.exams.length>0&&<section className="family-report-section family-report-exam-section"><i><HansalmaeIcon name="chart" size={18}/></i><div><b>개인별 시험 결과</b><div className="family-report-exams">{item.exams.map(exam=><div key={exam.id}><span><strong>{exam.examTitle||exam.examType||"시험"}</strong>{exam.evaluation&&<small>{exam.evaluation}</small>}</span><em>{exam.score===null?"평가":`${formatScore(exam.score)} / ${formatScore(exam.maxScore)}`}</em></div>)}</div></div></section>}
          {item.homeworkResult&&<section className="family-report-section"><i><HansalmaeIcon name="check" size={18}/></i><div><b>지난 숙제 검사</b><p><strong className={`homework-result ${item.homeworkResult.status}`}>{homeworkLabel[item.homeworkResult.status]??item.homeworkResult.status}</strong>{item.homeworkResult.note&&<span> · {item.homeworkResult.note}</span>}</p></div></section>}
          {item.homeworkContent&&<ReportSection icon="edit" title="과제 및 복습" text={item.homeworkContent}/>}
          {attendanceMemo&&<ReportSection icon="notice" title="출결 메모" text={attendanceMemo}/>}
        </div>
        {teacherFeedbacks.length>0&&<section className="family-teacher-feedback"><span className="family-teacher-feedback-icon"><HansalmaeIcon name="chat" size={19}/></span><div><b>{item.teacherName} 선생님 한마디</b>{teacherFeedbacks.map((feedback,index)=><p key={`${feedback.label}-${index}`}><strong>{feedback.label}</strong><span>{feedback.text}</span></p>)}</div></section>}
      </div>
      {readTracking&&<footer className="family-report-confirm"><span>{readAt?`확인 완료 · ${formatReadTime(readAt)}`:"내용을 확인했다면 표시를 남겨주세요."}</span>{!readAt&&<button type="button" disabled={confirming} onClick={onConfirm}><HansalmaeIcon name="check" size={16}/>{confirming?"처리 중…":"확인했어요"}</button>}</footer>}
    </section>
  </div>;
}

function ReportSection({icon,title,text}:{icon:"book"|"edit"|"notice"|"chart";title:string;text:string}){return <section className="family-report-section"><i><HansalmaeIcon name={icon} size={18}/></i><div><b>{title}</b><p>{text}</p></div></section>}
function dateValue(value:string){return new Date(`${value}T12:00:00+09:00`)}
function formatDateTitle(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"long",day:"numeric"}).format(dateValue(value))}
function formatDateWeekday(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",weekday:"long"}).format(dateValue(value))}
function formatFullDate(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",year:"numeric",month:"long",day:"numeric",weekday:"long"}).format(dateValue(value))}
function formatTime(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",hour:"2-digit",minute:"2-digit",hour12:false}).format(new Date(value))}
function formatReadTime(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"numeric",day:"numeric",hour:"2-digit",minute:"2-digit",hour12:false}).format(new Date(value))}
function formatScore(value:number){return Number.isInteger(Number(value))?String(Number(value)):Number(value).toFixed(1)}
