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

  useEffect(()=>{
    let active=true;
    setLoading(true);setUnavailable(false);setReadTracking(false);setReads({});
    void (async()=>{
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

  const subjects=useMemo(()=>Array.from(new Set(items.map(item=>item.subject).filter(Boolean))),[items]);
  useEffect(()=>{if(subject!=="전체"&&!subjects.includes(subject))setSubject("전체");},[subject,subjects]);
  const visibleItems=useMemo(()=>subject==="전체"?items:items.filter(item=>item.subject===subject),[items,subject]);
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
      <div><p className="eyebrow">한살매 학습 기록</p><h2>학습 리포트</h2><span>날짜별로 수업·시험·숙제와 선생님 피드백을 확인하세요.</span></div>
      {readTracking&&unreadCount>0&&<strong className="family-report-unread-count">새 리포트 {unreadCount}</strong>}
    </header>
    {subjects.length>1&&<nav className="family-report-subject-filter" aria-label="과목 필터"><button className={subject==="전체"?"active":""} onClick={()=>setSubject("전체")}>전체</button>{subjects.map(name=><button key={name} className={subject===name?"active":""} onClick={()=>setSubject(name)}>{name}</button>)}</nav>}
    {loading?<p className="family-report-empty">학습 리포트를 불러오는 중이에요…</p>:!items.length?<p className="family-report-empty">아직 등록된 수업 리포트가 없습니다.</p>:<div className="family-report-date-list">{groups.map(([date,reports])=><section className="family-report-date-group" key={date}><header><div><time>{formatDateTitle(date)}</time><span>{formatDateWeekday(date)}</span></div><small>{reports.length}개 수업 기록</small></header><div className="family-report-list">{reports.map(item=><ReportCard key={item.lessonId} item={item} readAt={reads[item.lessonId]??null} readTracking={readTracking} confirming={confirming===item.lessonId} onConfirm={()=>void confirmRead(item.lessonId)}/>)}</div></section>)}</div>}
  </section>;
}

function ReportCard({item,readAt,readTracking,confirming,onConfirm}:{item:Report;readAt:string|null;readTracking:boolean;confirming:boolean;onConfirm:()=>void}){
  const attendance=item.attendance;
  const teacherFeedbacks=item.exams.filter(exam=>exam.feedback.trim()).map(exam=>({label:exam.examTitle||exam.examType||"시험",text:exam.feedback.trim()}));
  const attendanceMemo=[attendance?.absenceReason,attendance?.note].filter(Boolean).join(" · ");
  return <article className={`family-report-card ${readTracking&&!readAt?"unread":""}`}>
    <header>
      <div className="family-report-subject"><div className="family-report-card-labels"><span>{item.subject}</span>{readTracking&&!readAt&&<em>NEW</em>}</div><h3>{item.className}</h3><small>{formatTime(item.startsAt)} · {item.teacherName}{item.room?` · ${item.room}`:""}</small></div>
      {attendance&&<strong className={`family-attendance-badge ${attendance.status}`}>{attendanceLabel[attendance.status]??attendance.status}{attendance.status==="late"&&attendance.lateMinutes?` ${attendance.lateMinutes}분`:""}</strong>}
    </header>
    <div className="family-report-body">
      {item.lessonContent&&<ReportSection icon="book" title="오늘 수업" text={item.lessonContent}/>} 
      {item.examContent&&<ReportSection icon="chart" title="오늘 시험·평가" text={item.examContent}/>} 
      {item.exams.length>0&&<section className="family-report-section family-report-exam-section"><i><HansalmaeIcon name="chart" size={18}/></i><div><b>개인별 시험 결과</b><div className="family-report-exams">{item.exams.map(exam=><div key={exam.id}><span><strong>{exam.examTitle||exam.examType||"시험"}</strong>{exam.evaluation&&<small>{exam.evaluation}</small>}</span><em>{exam.score===null?"평가":`${formatScore(exam.score)} / ${formatScore(exam.maxScore)}`}</em></div>)}</div></div></section>}
      {item.homeworkResult&&<section className="family-report-section"><i><HansalmaeIcon name="check" size={18}/></i><div><b>지난 숙제 검사</b><p><strong className={`homework-result ${item.homeworkResult.status}`}>{homeworkLabel[item.homeworkResult.status]??item.homeworkResult.status}</strong>{item.homeworkResult.note&&<span> · {item.homeworkResult.note}</span>}</p></div></section>}
      {item.homeworkContent&&<ReportSection icon="edit" title="오늘 숙제" text={item.homeworkContent}/>} 
      {attendanceMemo&&<ReportSection icon="notice" title="출결 메모" text={attendanceMemo}/>} 
    </div>
    {teacherFeedbacks.length>0&&<section className="family-teacher-feedback"><span className="family-teacher-feedback-icon"><HansalmaeIcon name="chat" size={19}/></span><div><b>{item.teacherName} 선생님 피드백</b>{teacherFeedbacks.map((feedback,index)=><p key={`${feedback.label}-${index}`}><strong>{feedback.label}</strong><span>{feedback.text}</span></p>)}</div></section>}
    {readTracking&&<footer className="family-report-confirm"><span>{readAt?`확인 완료 · ${formatReadTime(readAt)}`:"리포트를 확인했다면 완료 표시를 남겨주세요."}</span>{!readAt&&<button type="button" disabled={confirming} onClick={onConfirm}><HansalmaeIcon name="check" size={16}/>{confirming?"처리 중…":"확인했어요"}</button>}</footer>}
  </article>;
}

function ReportSection({icon,title,text}:{icon:"book"|"edit"|"notice"|"chart";title:string;text:string}){return <section className="family-report-section"><i><HansalmaeIcon name={icon} size={18}/></i><div><b>{title}</b><p>{text}</p></div></section>}
function dateValue(value:string){return new Date(`${value}T12:00:00+09:00`)}
function formatDateTitle(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"long",day:"numeric"}).format(dateValue(value))}
function formatDateWeekday(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",weekday:"long"}).format(dateValue(value))}
function formatTime(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",hour:"2-digit",minute:"2-digit",hour12:false}).format(new Date(value))}
function formatReadTime(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"numeric",day:"numeric",hour:"2-digit",minute:"2-digit",hour12:false}).format(new Date(value))}
function formatScore(value:number){return Number.isInteger(Number(value))?String(Number(value)):Number(value).toFixed(1)}
