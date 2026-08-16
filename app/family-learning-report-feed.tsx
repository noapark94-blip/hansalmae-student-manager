"use client";

import { useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { HansalmaeIcon } from "./hansalmae-icons";

type AttendanceInfo={status:string;lateMinutes:number|null;absenceReason:string;note:string}|null;
type HomeworkResult={status:string;note:string}|null;
type Exam={id:string;examType:string;examTitle:string;score:number|null;maxScore:number;percent:number|null;evaluation:string;feedback:string};
type Report={lessonId:string;lessonDate:string;startsAt:string;classId:string;className:string;subject:string;room:string|null;teacherName:string;lessonContent:string;homeworkContent:string;examContent:string;attendance:AttendanceInfo;homeworkResult:HomeworkResult;exams:Exam[]};

const attendanceLabel:Record<string,string>={present:"출석",late:"지각",absent:"결석",excused:"결석"};
const homeworkLabel:Record<string,string>={complete:"완료",partial:"일부 완료",missing:"미제출",excused:"확인 제외"};

export function FamilyLearningReportFeed({supabase,studentId}:{supabase:SupabaseClient;studentId:string}){
  const [items,setItems]=useState<Report[]>([]);
  const [loading,setLoading]=useState(true);
  const [unavailable,setUnavailable]=useState(false);
  useEffect(()=>{
    let active=true;
    setLoading(true);setUnavailable(false);
    void supabase.rpc("family_learning_reports",{p_student_id:studentId,p_limit:10}).then(({data,error})=>{
      if(!active)return;
      if(error){setUnavailable(true);setItems([]);}else setItems((data??[]) as Report[]);
      setLoading(false);
    });
    return()=>{active=false};
  },[studentId,supabase]);
  if(unavailable)return null;
  return <section className="family-report-feed" aria-label="수업 학습 리포트">
    <header className="family-report-feed-title"><div><p className="eyebrow">수업별 기록</p><h2>학습 리포트</h2><span>선생님이 수업에서 기록한 내용을 과목별로 확인할 수 있어요.</span></div></header>
    {loading?<p className="family-report-empty">학습 리포트를 불러오는 중이에요…</p>:!items.length?<p className="family-report-empty">아직 등록된 수업 리포트가 없습니다.</p>:<div className="family-report-list">{items.map(item=><ReportCard key={item.lessonId} item={item}/>)}</div>}
  </section>;
}

function ReportCard({item}:{item:Report}){
  const attendance=item.attendance;
  return <article className="family-report-card">
    <header>
      <div className="family-report-subject"><span>{item.subject}</span><h3>{item.className}</h3><small>{formatDate(item.lessonDate)} · {formatTime(item.startsAt)} · {item.teacherName}{item.room?` · ${item.room}`:""}</small></div>
      {attendance&&<strong className={`family-attendance-badge ${attendance.status}`}>{attendanceLabel[attendance.status]??attendance.status}{attendance.status==="late"&&attendance.lateMinutes?` ${attendance.lateMinutes}분`:""}</strong>}
    </header>
    <div className="family-report-body">
      {item.lessonContent&&<ReportSection icon="book" title="오늘 수업" text={item.lessonContent}/>} 
      {item.exams.length>0&&<section className="family-report-section"><i><HansalmaeIcon name="chart" size={18}/></i><div><b>개인별 시험</b><div className="family-report-exams">{item.exams.map(exam=><div key={exam.id}><span><strong>{exam.examTitle||exam.examType||"시험"}</strong>{exam.evaluation&&<small>{exam.evaluation}</small>}</span><em>{exam.score===null?"평가":`${formatScore(exam.score)} / ${formatScore(exam.maxScore)}`}</em>{exam.feedback&&<p>{exam.feedback}</p>}</div>)}</div></div></section>}
      {item.homeworkResult&&<section className="family-report-section"><i><HansalmaeIcon name="check" size={18}/></i><div><b>지난 숙제 검사</b><p><strong className={`homework-result ${item.homeworkResult.status}`}>{homeworkLabel[item.homeworkResult.status]??item.homeworkResult.status}</strong>{item.homeworkResult.note&&<span> · {item.homeworkResult.note}</span>}</p></div></section>}
      {item.homeworkContent&&<ReportSection icon="edit" title="오늘 숙제" text={item.homeworkContent}/>} 
      {attendance?.absenceReason&&<ReportSection icon="notice" title="출결 메모" text={attendance.absenceReason}/>} 
    </div>
  </article>;
}

function ReportSection({icon,title,text}:{icon:"book"|"edit"|"notice";title:string;text:string}){return <section className="family-report-section"><i><HansalmaeIcon name={icon} size={18}/></i><div><b>{title}</b><p>{text}</p></div></section>}
function formatDate(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"long",day:"numeric",weekday:"short"}).format(new Date(`${value}T12:00:00+09:00`))}
function formatTime(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",hour:"2-digit",minute:"2-digit",hour12:false}).format(new Date(value))}
function formatScore(value:number){return Number.isInteger(Number(value))?String(Number(value)):Number(value).toFixed(1)}
