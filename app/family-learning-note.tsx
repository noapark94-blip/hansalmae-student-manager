"use client";

import { useEffect, useState } from "react";
import { HansalmaeIcon } from "./hansalmae-icons";

type Attendance = { id:string; lessonDate:string; className:string; status:string; note:string|null };
type Assignment = { id:string; title:string; className:string; dueAt:string; status:string; feedback:string|null };
type Announcement = { id:string; title:string; body:string; publishedAt:string; authorName:string };
type FamilyView = "attendance"|"assignments"|"communications";
export type TodayLesson = { id:string; kind:string; label:string; subject:string; startTime:string; endTime:string; teacherName:string; room:string; attendanceStatus:string|null };
export type NextLesson = { classDate:string; startTime:string; subject:string; name:string };

const attendanceLabel:Record<string,string>={present:"출석",late:"지각",absent:"결석",excused:"결석"};

export function FamilyLearningNote({studentName,attendance,assignments,announcements,todayLessons,nextLesson,onNavigate,onSchedule}:{studentName:string;attendance:Attendance[];assignments:Assignment[];announcements:Announcement[];todayLessons:TodayLesson[];nextLesson:NextLesson|null;onNavigate:(view:FamilyView)=>void;onSchedule:()=>void}){
  const [summaryOpen,setSummaryOpen]=useState(false);
  const [now,setNow]=useState(()=>new Date());
  useEffect(()=>{const timer=window.setInterval(()=>setNow(new Date()),30000);return()=>window.clearInterval(timer)},[]);
  const today=seoulDate();
  const todayAttendance=attendance.filter(item=>item.lessonDate.slice(0,10)===today);
  const activeAssignments=assignments.filter(item=>item.status!=="reviewed").slice(0,3);
  const latestNotice=announcements[0]??null;
  const presentCount=todayLessons.filter(item=>item.attendanceStatus==="present").length;
  const lateCount=todayLessons.filter(item=>item.attendanceStatus==="late").length;
  const absentCount=todayLessons.filter(item=>["absent","excused"].includes(item.attendanceStatus??"")).length;
  const checkedCount=presentCount+lateCount+absentCount;
  const currentMinute=seoulMinute(now);
  const liveLesson=todayLessons.find(item=>item.attendanceStatus==="present"&&isLessonLive(item,now))??null;
  const nextTodayLesson=[...todayLessons].sort((a,b)=>a.startTime.localeCompare(b.startTime)).find(item=>timeMinute(item.startTime)>currentMinute)??null;
  const allFinished=todayLessons.length>0&&todayLessons.every(item=>timeMinute(item.endTime)<=currentMinute);
  const liveStatus=liveLesson
    ? {tone:"live",title:`${liveLesson.subject} 수업 중`,detail:`${liveLesson.startTime.slice(0,5)}–${liveLesson.endTime.slice(0,5)}`}
    : nextTodayLesson
      ? {tone:"waiting",title:"수업 시작 전",detail:`${nextTodayLesson.subject} · ${nextTodayLesson.startTime.slice(0,5)}`}
      : allFinished
        ? {tone:"done",title:"오늘 수업 완료",detail:`출결 ${checkedCount}/${todayLessons.length} 확인`}
        : {tone:"waiting",title:"다음 수업 대기",detail:"오늘 일정을 확인해 주세요"};
  return <section className={`family-learning-note${todayLessons.length?"":" no-lessons"}`} aria-label="오늘의 학습 노트">
    <header>
      <div className="family-note-date"><span>{formatToday()}</span><b>오늘의 한살매</b></div>
      <div><h2>{studentName} 학습 노트</h2><p>오늘의 수업과 해야 할 일을 한눈에 확인하세요.</p></div>
    </header>
    <div className={`family-note-summary${todayLessons.length?"":" empty"}`}>
      {todayLessons.length?<><button type="button" className="family-note-overview" aria-expanded={summaryOpen} onClick={()=>setSummaryOpen(value=>!value)}><HansalmaeIcon name="calendar" size={17}/><b>오늘 수업 {todayLessons.length}개</b></button><div className={`family-note-live-status ${liveStatus.tone}`} aria-label={`실시간 상태: ${liveStatus.title}`} aria-live="polite"><i aria-hidden="true"/><span><b>{liveStatus.title}</b><small>{liveStatus.detail}</small></span></div></>:<button type="button" className="family-note-no-lessons" onClick={onSchedule} aria-label="시간표에서 다음 수업 확인">
        <i><HansalmaeIcon name="calendar" size={18}/></i>
        <span><b>오늘은 예정된 수업이 없어요</b>{nextLesson&&<small>다음 수업 · {formatNextLesson(nextLesson)}</small>}</span>
        <em aria-hidden="true">›</em>
      </button>}
    </div>
    {summaryOpen&&<section className="family-note-today-detail">
      <header><b>오늘의 수업</b><button type="button" onClick={()=>setSummaryOpen(false)}>닫기</button></header>
      {todayLessons.length?<div>{todayLessons.map(item=>{const live=item.attendanceStatus==="present"&&isLessonLive(item,now);return <article key={item.id}><time>{item.startTime.slice(0,5)}</time><span><b>{item.subject} {item.label}</b><small>{[item.teacherName,item.room].filter(Boolean).join(" · ")}</small></span><em className={live?"live":item.attendanceStatus??"pending"}>{live?<><i/>수업 중</>:attendanceLabel[item.attendanceStatus??""]??"입력 전"}</em></article>})}</div>:<p>오늘 예정된 수업이 없습니다.</p>}
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
function formatNextLesson(item:NextLesson){
  const date=new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"numeric",day:"numeric",weekday:"short"}).format(new Date(`${item.classDate}T00:00:00+09:00`));
  return `${date} · ${item.subject||item.name} · ${item.startTime.slice(0,5)}`;
}
function isLessonLive(item:TodayLesson,now:Date){
  const current=seoulMinute(now),start=timeMinute(item.startTime),end=timeMinute(item.endTime);
  return current>=start&&current<end;
}
function seoulMinute(now:Date){const parts=new Intl.DateTimeFormat("en-GB",{timeZone:"Asia/Seoul",hour:"2-digit",minute:"2-digit",hourCycle:"h23"}).format(now).split(":").map(Number);return parts[0]*60+parts[1]}
function timeMinute(value:string){const parts=value.slice(0,5).split(":").map(Number);return parts[0]*60+parts[1]}
