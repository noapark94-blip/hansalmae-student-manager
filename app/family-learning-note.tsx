"use client";

import { HansalmaeIcon } from "./hansalmae-icons";

type Attendance = { id:string; lessonDate:string; className:string; status:string; note:string|null };
type Assignment = { id:string; title:string; className:string; dueAt:string; status:string; feedback:string|null };
type Announcement = { id:string; title:string; body:string; publishedAt:string; authorName:string };
type FamilyView = "attendance"|"assignments"|"communications";

const attendanceLabel:Record<string,string>={present:"출석",late:"지각",absent:"결석",excused:"결석"};

export function FamilyLearningNote({studentName,attendance,assignments,announcements,todayClassCount,onNavigate}:{studentName:string;attendance:Attendance[];assignments:Assignment[];announcements:Announcement[];todayClassCount:number;onNavigate:(view:FamilyView)=>void}){
  const today=seoulDate();
  const todayAttendance=attendance.filter(item=>item.lessonDate.slice(0,10)===today);
  const activeAssignments=assignments.filter(item=>item.status!=="reviewed").slice(0,3);
  const latestNotice=announcements[0]??null;
  const completeCount=todayAttendance.filter(item=>item.status==="present").length;
  return <section className="family-learning-note" aria-label="오늘의 학습 노트">
    <header>
      <div className="family-note-date"><span>{formatToday()}</span><b>오늘의 한살매</b></div>
      <div><h2>{studentName} 학습 노트</h2><p>오늘의 수업과 해야 할 일을 한눈에 확인하세요.</p></div>
    </header>
    <div className="family-note-summary">
      <span><HansalmaeIcon name="check" size={17}/><b>{todayAttendance.length?`${completeCount}/${todayAttendance.length} 수업 출석` : "오늘 출결 전"}</b></span>
      <span><HansalmaeIcon name="calendar" size={17}/><b>오늘 수업 {todayClassCount}개</b></span>
    </div>
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
