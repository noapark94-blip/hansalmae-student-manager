"use client";

import { useState } from "react";
import { HansalmaeIcon } from "./hansalmae-icons";

type Attendance = { id:string; lessonDate:string; className:string; status:string; note:string|null };
type Assignment = { id:string; title:string; className:string; dueAt:string; status:string; feedback:string|null };
type Announcement = { id:string; title:string; body:string; publishedAt:string; authorName:string };
type FamilyView = "attendance"|"assignments"|"communications";
export type TodayLesson = { id:string; kind:string; label:string; subject:string; startTime:string; endTime:string; teacherName:string; room:string; attendanceStatus:string|null };

const attendanceLabel:Record<string,string>={present:"출석",late:"지각",absent:"결석",excused:"결석"};

export function FamilyLearningNote({studentName,attendance,assignments,announcements,todayLessons,onNavigate}:{studentName:string;attendance:Attendance[];assignments:Assignment[];announcements:Announcement[];todayLessons:TodayLesson[];onNavigate:(view:FamilyView)=>void}){
  const [summaryOpen,setSummaryOpen]=useState<"attendance"|"lessons"|null>(null);
  const today=seoulDate();
  const todayAttendance=attendance.filter(item=>item.lessonDate.slice(0,10)===today);
  const activeAssignments=assignments.filter(item=>item.status!=="reviewed").slice(0,3);
  const latestNotice=announcements[0]??null;
  const presentCount=todayLessons.filter(item=>item.attendanceStatus==="present").length;
  const lateCount=todayLessons.filter(item=>item.attendanceStatus==="late").length;
  const absentCount=todayLessons.filter(item=>["absent","excused"].includes(item.attendanceStatus??"")).length;
  const checkedCount=presentCount+lateCount+absentCount;
  const attendanceText=!todayLessons.length?"오늘 수업 없음":!checkedCount?"오늘 출결 전":[presentCount&&`출석 ${presentCount}`,lateCount&&`지각 ${lateCount}`,absentCount&&`결석 ${absentCount}`].filter(Boolean).join(" · ");
  return <section className="family-learning-note" aria-label="오늘의 학습 노트">
    <header>
      <div className="family-note-date"><span>{formatToday()}</span><b>오늘의 한살매</b></div>
      <div><h2>{studentName} 학습 노트</h2><p>오늘의 수업과 해야 할 일을 한눈에 확인하세요.</p></div>
    </header>
    <div className="family-note-summary">
      <button type="button" aria-expanded={summaryOpen==="attendance"} onClick={()=>setSummaryOpen(value=>value==="attendance"?null:"attendance")}><HansalmaeIcon name="check" size={17}/><b>{attendanceText}</b></button>
      <button type="button" aria-expanded={summaryOpen==="lessons"} onClick={()=>setSummaryOpen(value=>value==="lessons"?null:"lessons")}><HansalmaeIcon name="calendar" size={17}/><b>오늘 수업 {todayLessons.length}개</b></button>
    </div>
    {summaryOpen&&<section className="family-note-today-detail">
      <header><b>{summaryOpen==="attendance"?"오늘의 출결":"오늘의 수업"}</b><button type="button" onClick={()=>setSummaryOpen(null)}>닫기</button></header>
      {todayLessons.length?<div>{todayLessons.map(item=><article key={item.id}><time>{item.startTime.slice(0,5)}</time><span><b>{item.subject} {item.label}</b><small>{[item.teacherName,item.room].filter(Boolean).join(" · ")}</small></span><em className={item.attendanceStatus??"pending"}>{attendanceLabel[item.attendanceStatus??""]??"입력 전"}</em></article>)}</div>:<p>오늘 예정된 수업이 없습니다.</p>}
    </section>}
    <div className="family-note-grid">
      <button type="button" className="family-note-block" onClick={()=>onNavigate("attendance")}>
        <i className="green"><HansalmaeIcon name="check" size={20}/></i>
        <span><small>오늘의 출결</small>{todayAttendance.length?todayAttendance.map(item=><b key={item.id}>{item.className} · {attendanceLabel[item.status]??item.status}</b>):<b>아직 입력된 출결이 없습니다.</b>}<em>출결 기록 보기</em></span>
      </button>
      <button type="button" className="family-note-block" onClick={()=>onNavigate("assignments")}>
        <i className="wine"><HansalmaeIcon name="edit" size={20}/></i>
        <span><small>해야 할 학습</small>{activeAssignments.length?activeAssignments.map(item=><b key={item.id}>{item.className} · {item.title}</b>):<b>현재 진행 중인 과제가 없습니다.</b>}<em>과제·첨삭 보기</em></span>
      </button>
      <button type="button" className="family-note-block wide" onClick={()=>onNavigate("communications")}>
        <i className="blue"><HansalmaeIcon name="notice" size={20}/></i>
        <span><small>학원 소식</small><b>{latestNotice?.title??"새로운 공지가 없습니다."}</b>{latestNotice&&<p>{latestNotice.body}</p>}<em>공지 전체 보기</em></span>
      </button>
    </div>
  </section>;
}

function seoulDate(){return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date());}
function formatToday(){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"long",day:"numeric",weekday:"short"}).format(new Date());}
