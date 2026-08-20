"use client";

import { useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type AttendanceInfo={status:string;lateMinutes:number|null;absenceReason:string;note:string}|null;
type HomeworkResult={status:string;note:string}|null;
type Exam={id:string;examType:string;examTitle:string;score:number|null;maxScore:number;percent:number|null;evaluation:string;feedback:string};
type Report={lessonId:string;lessonDate:string;startsAt:string;classId:string;className:string;subject:string;room:string|null;teacherName:string;lessonContent:string;homeworkContent:string;examContent:string;attendance:AttendanceInfo;homeworkResult:HomeworkResult;exams:Exam[]};

const attendanceLabel:Record<string,string>={present:"출석",late:"지각",absent:"결석",excused:"결석"};
const homeworkLabel:Record<string,string>={complete:"완료",partial:"일부 완료",missing:"미제출",excused:"확인 제외"};
const weekdays=["일","월","화","수","목","금","토"];

export function StudentLearningHistory({supabase,studentId}:{supabase:SupabaseClient;studentId:string}){
  const [items,setItems]=useState<Report[]>([]);
  const [loading,setLoading]=useState(true);
  const [error,setError]=useState("");
  const [subject,setSubject]=useState("전체");
  const [month,setMonth]=useState(()=>monthKey(new Date()));
  const [selectedDate,setSelectedDate]=useState("");

  useEffect(()=>{
    let active=true;
    setLoading(true);setError("");
    void supabase.rpc("staff_student_completed_learning_history",{p_student_id:studentId,p_limit:300}).then(({data,error:loadError})=>{
      if(!active)return;
      if(loadError){setError("수업 기록을 불러오지 못했습니다.");setItems([]);setLoading(false);return;}
      const rows=((data??[]) as Report[]).slice().sort((a,b)=>b.lessonDate.localeCompare(a.lessonDate)||String(b.startsAt).localeCompare(String(a.startsAt)));
      setItems(rows);
      if(rows.length){const latest=rows[0].lessonDate;setMonth(latest.slice(0,7));setSelectedDate(latest)}
      setLoading(false);
    });
    return()=>{active=false};
  },[studentId,supabase]);

  const subjects=useMemo(()=>Array.from(new Set(items.map(item=>item.subject).filter(Boolean))),[items]);
  const filtered=useMemo(()=>subject==="전체"?items:items.filter(item=>item.subject===subject),[items,subject]);
  const dates=useMemo(()=>new Set(filtered.map(item=>item.lessonDate)),[filtered]);
  const selected=useMemo(()=>filtered.filter(item=>item.lessonDate===selectedDate),[filtered,selectedDate]);
  const calendar=useMemo(()=>buildCalendar(month),[month]);
  const examRows=useMemo(()=>filtered.flatMap(item=>item.exams),[filtered]);
  const scoredExams=useMemo(()=>examRows.map(exam=>exam.percent??(exam.score!==null&&exam.maxScore>0?exam.score/exam.maxScore*100:null)).filter((value):value is number=>value!==null&&Number.isFinite(value)),[examRows]);
  const examAverage=scoredExams.length?Math.round(scoredExams.reduce((sum,value)=>sum+value,0)/scoredExams.length*10)/10:null;

  useEffect(()=>{if(subject!=="전체"&&!subjects.includes(subject))setSubject("전체")},[subject,subjects]);
  useEffect(()=>{if(selectedDate&&dates.has(selectedDate)&&selectedDate.startsWith(month))return;setSelectedDate(filtered.find(item=>item.lessonDate.startsWith(month))?.lessonDate??"")},[filtered,month,dates,selectedDate]);

  const moveMonth=(delta:number)=>{const[year,m]=month.split("-").map(Number);setMonth(monthKey(new Date(year,m-1+delta,1)))};

  return <section className="student-learning-history">
    <section className="student-learning-summary">
      <article><small>누적 수업 기록</small><b>{filtered.length}<em>회</em></b></article>
      <article><small>시험 기록</small><b>{examRows.length}<em>회</em></b></article>
      <article><small>시험 평균</small><b>{examAverage===null?"—":examAverage}<em>{examAverage===null?"":"점"}</em></b></article>
    </section>

    <nav className="student-learning-subject-tabs">
      <button className={subject==="전체"?"active":""} onClick={()=>setSubject("전체")}>전체</button>
      {subjects.map(name=><button key={name} className={subject===name?"active":""} onClick={()=>setSubject(name)}>{name}</button>)}
    </nav>

    {loading?<p className="student-learning-empty">수업 기록을 불러오는 중이에요…</p>:error?<p className="student-learning-empty error">{error}</p>:!items.length?<p className="student-learning-empty">아직 저장된 수업 기록이 없습니다.</p>:<section className="student-learning-history-grid">
      <section className="student-learning-calendar-panel">
        <header className="student-learning-calendar-head"><button type="button" onClick={()=>moveMonth(-1)} aria-label="이전 달">‹</button><b>{formatMonth(month)}</b><button type="button" onClick={()=>moveMonth(1)} aria-label="다음 달">›</button></header>
        <div className="student-learning-weekdays">{weekdays.map((day,index)=><span className={index===0?"sun":index===6?"sat":""} key={day}>{day}</span>)}</div>
        <div className="student-learning-days">{calendar.map((day,index)=>day?<button type="button" key={day} className={`${dates.has(day)?"has-record":""} ${selectedDate===day?"selected":""}`} onClick={()=>dates.has(day)&&setSelectedDate(day)} disabled={!dates.has(day)}><span>{Number(day.slice(8))}</span>{dates.has(day)&&<small>{recordDayLabel(filtered,day)}</small>}</button>:<span className="blank" key={`blank-${index}`}/>)}</div>
      </section>

      <section className="student-learning-selected">
        <header><div><small>선택한 날짜</small><b>{selectedDate?formatDateTitle(selectedDate):"기록 없음"}</b></div>{selectedDate&&<em>{selected.length}건</em>}</header>
        {selected.length?<div className="student-learning-cards">{selected.map(item=><LearningRecordCard key={item.lessonId} item={item}/>)}</div>:<div className="student-learning-no-selection">이 달에는 저장된 수업 기록이 없습니다.</div>}
      </section>
    </section>}
  </section>;
}

function LearningRecordCard({item}:{item:Report}){
  const attendance=item.attendance;
  const attendanceMemo=[attendance?.absenceReason,attendance?.note].filter(Boolean).join(" · ");
  return <article className="student-learning-card">
    <header><div><span>{item.subject} 수업</span><h4>{item.className}</h4><small>{formatTime(item.startsAt)} · 담당 {item.teacherName}{item.room?` · ${item.room}`:""}</small></div>{attendance&&<strong className={attendance.status}>{attendanceLabel[attendance.status]??attendance.status}{attendance.status==="late"&&attendance.lateMinutes?` ${attendance.lateMinutes}분`:""}</strong>}</header>
    <div className="student-learning-card-body">
      {item.lessonContent&&<RecordRow label="수업 내용" text={item.lessonContent}/>} 
      {item.homeworkResult&&<RecordRow label="지난 숙제 검사" text={`${homeworkLabel[item.homeworkResult.status]??item.homeworkResult.status}${item.homeworkResult.note?` · ${item.homeworkResult.note}`:""}`}/>} 
      {item.homeworkContent&&<RecordRow label="오늘 숙제" text={item.homeworkContent}/>} 
      {item.examContent&&<RecordRow label="시험·평가" text={item.examContent}/>} 
      {item.exams.length>0&&<section className="student-learning-exams"><b>시험 기록</b>{item.exams.map(exam=><div key={exam.id}><span><strong>{exam.examTitle||exam.examType||"시험"}</strong>{exam.evaluation&&<small>{exam.evaluation}</small>}{exam.feedback&&<small>{exam.feedback}</small>}</span><em>{exam.score===null?"평가":`${formatScore(exam.score)} / ${formatScore(exam.maxScore)}`}</em></div>)}</section>}
      {attendanceMemo&&<RecordRow label="출결 메모" text={attendanceMemo}/>} 
    </div>
  </article>
}
function RecordRow({label,text}:{label:string;text:string}){return <section className="student-learning-row"><b>{label}</b><p>{text}</p></section>}
function recordDayLabel(items:Report[],day:string){const dayItems=items.filter(item=>item.lessonDate===day);if(!dayItems.length)return"";const labels=Array.from(new Set(dayItems.map(item=>item.attendance?attendanceLabel[item.attendance.status]??item.attendance.status:"").filter(Boolean)));return labels.length>1?`${labels[0]} 외 ${labels.length-1}`:(labels[0]??"출결 기록")}
function buildCalendar(month:string){const[y,m]=month.split("-").map(Number);const first=new Date(y,m-1,1);const count=new Date(y,m,0).getDate();const values:(string|null)[]=Array(first.getDay()).fill(null);for(let d=1;d<=count;d++)values.push(`${y}-${String(m).padStart(2,"0")}-${String(d).padStart(2,"0")}`);while(values.length%7)values.push(null);return values}
function monthKey(date:Date){return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,"0")}`}
function formatMonth(value:string){const[y,m]=value.split("-").map(Number);return `${y}년 ${m}월`}
function dateValue(value:string){return new Date(`${value}T12:00:00+09:00`)}
function formatDateTitle(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",year:"numeric",month:"long",day:"numeric",weekday:"short"}).format(dateValue(value))}
function formatTime(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",hour:"2-digit",minute:"2-digit",hour12:false}).format(new Date(value))}
function formatScore(value:number){return Number.isInteger(Number(value))?String(Number(value)):Number(value).toFixed(1)}
