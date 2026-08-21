"use client";

import { useEffect,useMemo,useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type StudentInfo={studentId:string;studentName:string;school:string|null;grade:string|null;subject:string};
type Row={
  id:string;correction_date:string;start_time:string;end_time:string;subject:string;
  attendance_status:string;late_minutes:number|null;absence_reason:string|null;exam_title:string|null;exam_range:string|null;
  exam_score:number|null;exam_max_score:number|null;evaluation:string|null;homework_status:string|null;correction_content:string|null;recorded_by_name:string|null;
};

const attendanceLabel:Record<string,string>={scheduled:"미기록",present:"출석",late:"지각",absent:"결석"};
const weekdays=["일","월","화","수","목","금","토"];

export function CorrectionHistoryModal({supabase,student,onClose}:{supabase:SupabaseClient;student:StudentInfo;onClose:()=>void}){
  const[items,setItems]=useState<Row[]>([]);
  const[loading,setLoading]=useState(true);
  const[error,setError]=useState("");
  const[subject,setSubject]=useState("전체");
  const[month,setMonth]=useState(()=>monthKey(new Date()));
  const[selectedDate,setSelectedDate]=useState<string|null>(null);

  useEffect(()=>{let active=true;setLoading(true);setError("");void(async()=>{
    const response=await supabase.from("correction_reports")
      .select("id,correction_date,start_time,end_time,subject,attendance_status,late_minutes,absence_reason,exam_title,exam_range,exam_score,exam_max_score,evaluation,homework_status,correction_content,recorded_by_name")
      .eq("student_id",student.studentId)
      .eq("published",true)
      .in("attendance_status",["present","late","absent"])
      .order("correction_date",{ascending:false})
      .order("start_time",{ascending:false})
      .limit(100);
    if(!active)return;
    if(response.error){setError("과거 첨삭 기록을 불러오지 못했습니다.");setItems([])}else{
      const rows=(response.data??[]) as Row[];
      setItems(rows);
      if(rows[0]){setSelectedDate(rows[0].correction_date);setMonth(rows[0].correction_date.slice(0,7))}
    }
    setLoading(false);
  })();return()=>{active=false}},[student.studentId,supabase]);

  const subjects=useMemo(()=>["전체",...Array.from(new Set(items.map(item=>item.subject)))],[items]);
  const visible=useMemo(()=>subject==="전체"?items:items.filter(item=>item.subject===subject),[items,subject]);
  const scored=visible.filter(item=>item.exam_score!=null&&item.exam_max_score!=null&&Number(item.exam_max_score)>0);
  const average=scored.length?Math.round(scored.reduce((sum,item)=>sum+Number(item.exam_score)/Number(item.exam_max_score)*100,0)/scored.length*10)/10:null;
  const homeworkRows=visible.filter(item=>item.homework_status);
  const homeworkRate=homeworkRows.length?Math.round(homeworkRows.filter(item=>item.homework_status==="complete").length/homeworkRows.length*100):null;
  const byDate=useMemo(()=>{const map=new Map<string,Row[]>();for(const item of visible){const list=map.get(item.correction_date)??[];list.push(item);map.set(item.correction_date,list)}return map},[visible]);
  const calendarDays=useMemo(()=>buildCalendar(month),[month]);
  const selectedItems=selectedDate?(byDate.get(selectedDate)??[]):[];

  useEffect(()=>{
    if(!visible.length){setSelectedDate(null);return}
    if(selectedDate&&visible.some(item=>item.correction_date===selectedDate))return;
    setSelectedDate(visible[0].correction_date);
    setMonth(visible[0].correction_date.slice(0,7));
  },[subject,visible,selectedDate]);

  return <div className="correction-history-backdrop" role="presentation" onMouseDown={e=>{if(e.currentTarget===e.target)onClose()}}>
    <section className="correction-history-modal correction-history-calendar-modal" role="dialog" aria-modal="true" aria-label={`${student.studentName} 첨삭 기록`}>
      <header>
        <div><p className="eyebrow">교직원 전용 · 누적 첨삭 기록</p><h2>{student.studentName}<small className="history-type-label">첨삭 기록</small></h2><span>{[student.school,student.grade].filter(Boolean).join(" · ")||"학생 정보"}</span></div>
        <button type="button" className="modal-close" aria-label="닫기" onClick={onClose}>×</button>
      </header>
      <div className="correction-history-summary">
        <div><small>누적 첨삭</small><b>{visible.length}<em>회</em></b></div>
        <div><small>과제 완료율</small><b>{homeworkRate==null?"—":homeworkRate}<em>{homeworkRate==null?"":"%"}</em></b></div>
        <div><small>시험 평균</small><b>{average==null?"—":average}<em>{average==null?"":"점"}</em></b></div>
      </div>
      <nav className="correction-history-filter" aria-label="과목 필터">{subjects.map(value=><button type="button" key={value} className={subject===value?"active":""} onClick={()=>setSubject(value)}>{value}</button>)}</nav>

      {loading?<p className="correction-history-empty">첨삭 기록을 불러오는 중이에요…</p>:error?<p className="correction-history-error">{error}</p>:!visible.length?<p className="correction-history-empty">저장된 첨삭 기록이 없습니다.</p>:<div className="correction-history-calendar-wrap">
        <section className="correction-history-calendar">
          <div className="correction-history-calendar-toolbar">
            <button type="button" onClick={()=>setMonth(shiftMonth(month,-1))}>‹</button>
            <strong>{formatMonth(month)}</strong>
            <button type="button" onClick={()=>setMonth(shiftMonth(month,1))}>›</button>
          </div>
          <div className="correction-history-weekdays">{weekdays.map(day=><b key={day}>{day}</b>)}</div>
          <div className="correction-history-calendar-grid">{calendarDays.map((day,index)=>{
            if(!day)return <span className="blank" key={`blank-${index}`}/>;
            const records=byDate.get(day)??[];
            const selected=selectedDate===day;
            return <button type="button" key={day} className={`${records.length?"has-record":""}${selected?" selected":""}`} onClick={()=>records.length&&setSelectedDate(day)} disabled={!records.length}>
              <span>{Number(day.slice(-2))}</span>
              {records.length?<div>{records.slice(0,2).map(record=><em key={record.id} className={record.attendance_status}>{record.subject} · {attendanceLabel[record.attendance_status]??record.attendance_status}</em>)}{records.length>2?<small>+{records.length-2}</small>:null}</div>:null}
            </button>
          })}</div>
        </section>
        <section className="correction-history-day-panel">
          <header><div><small>선택한 날짜</small><h3>{selectedDate?formatDate(selectedDate):"기록 날짜를 선택하세요"}</h3></div>{selectedItems.length?<span>{selectedItems.length}건</span>:null}</header>
          <div className="correction-history-day-list">{selectedItems.length?selectedItems.map(item=><HistoryCard key={item.id} item={item}/>):<p>캘린더에서 기록이 있는 날짜를 선택하세요.</p>}</div>
        </section>
      </div>}
    </section>
  </div>;
}

function HistoryCard({item}:{item:Row}){
  const max=item.exam_max_score??100;
  const converted=item.exam_score==null||Number(max)<=0?null:Math.round(Number(item.exam_score)/Number(max)*1000)/10;
  return <article className="correction-history-day-card">
    <header><div><b>{item.subject} 첨삭</b><span>{item.start_time.slice(0,5)}–{item.end_time.slice(0,5)}</span></div><strong className={item.attendance_status}>{attendanceLabel[item.attendance_status]??item.attendance_status}{item.attendance_status==="late"&&item.late_minutes?` ${item.late_minutes}분`:item.attendance_status==="absent"&&item.absence_reason?` · ${item.absence_reason}`:""}</strong></header>
    <div className="correction-history-meta"><span>첨삭 담당</span><b>{item.recorded_by_name||"기록 없음"}</b></div>
    {item.exam_title?<section className="correction-history-block exam"><small>시험 기록</small><h3>{item.exam_title}</h3><p>{[cleanRange(item.exam_range),item.exam_score==null?null:`${formatScore(item.exam_score)} / ${formatScore(max)}점${converted==null?"":` · 환산 ${converted}점`}`,item.evaluation].filter(Boolean).join(" · ")}</p></section>:null}
    {item.correction_content?<section className="correction-history-block task"><small>오늘 한 첨삭과제</small><p>{item.correction_content}</p></section>:null}
    {!item.exam_title&&!item.correction_content?<p className="correction-history-no-detail">출결만 기록된 첨삭입니다.</p>:null}
  </article>;
}

function cleanRange(value:string|null){return (value??"").replace(/^\[종류\][^\n]*\n?/,"").trim()}
function formatDate(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",year:"numeric",month:"long",day:"numeric",weekday:"short"}).format(new Date(`${value}T12:00:00+09:00`))}
function formatScore(value:number){return Number.isInteger(Number(value))?String(Number(value)):Number(value).toFixed(1)}
function monthKey(date:Date){return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,"0")}`}
function formatMonth(value:string){const[y,m]=value.split("-");return `${y}년 ${Number(m)}월`}
function shiftMonth(value:string,amount:number){const[y,m]=value.split("-").map(Number);return monthKey(new Date(y,m-1+amount,1))}
function buildCalendar(value:string){const[y,m]=value.split("-").map(Number);const first=new Date(y,m-1,1);const count=new Date(y,m,0).getDate();const days:(string|null)[]=Array(first.getDay()).fill(null);for(let day=1;day<=count;day++)days.push(`${y}-${String(m).padStart(2,"0")}-${String(day).padStart(2,"0")}`);while(days.length%7)days.push(null);return days}
