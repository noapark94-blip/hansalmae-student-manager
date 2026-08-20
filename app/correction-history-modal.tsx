"use client";

import { useEffect,useMemo,useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type StudentInfo={studentId:string;studentName:string;school:string|null;grade:string|null;subject:string};
type Row={
  id:string;correction_date:string;start_time:string;end_time:string;subject:string;
  attendance_status:string;late_minutes:number|null;exam_title:string|null;exam_range:string|null;
  exam_score:number|null;exam_max_score:number|null;evaluation:string|null;correction_content:string|null;recorded_by_name:string|null;
};

const attendanceLabel:Record<string,string>={scheduled:"미기록",present:"출석",late:"지각",absent:"결석"};

export function CorrectionHistoryModal({supabase,student,onClose}:{supabase:SupabaseClient;student:StudentInfo;onClose:()=>void}){
  const[items,setItems]=useState<Row[]>([]);
  const[loading,setLoading]=useState(true);
  const[error,setError]=useState("");
  const[subject,setSubject]=useState("전체");

  useEffect(()=>{let active=true;setLoading(true);setError("");void(async()=>{
    const response=await supabase.from("correction_reports")
      .select("id,correction_date,start_time,end_time,subject,attendance_status,late_minutes,exam_title,exam_range,exam_score,exam_max_score,evaluation,correction_content,recorded_by_name")
      .eq("student_id",student.studentId)
      .order("correction_date",{ascending:false})
      .order("start_time",{ascending:false})
      .limit(50);
    if(!active)return;
    if(response.error){setError("과거 첨삭 기록을 불러오지 못했습니다.");setItems([])}else setItems((response.data??[]) as Row[]);
    setLoading(false);
  })();return()=>{active=false}},[student.studentId,supabase]);

  const subjects=useMemo(()=>["전체",...Array.from(new Set(items.map(item=>item.subject)))],[items]);
  const visible=useMemo(()=>subject==="전체"?items:items.filter(item=>item.subject===subject),[items,subject]);
  const scored=visible.filter(item=>item.exam_score!=null&&item.exam_max_score!=null&&Number(item.exam_max_score)>0);
  const average=scored.length?Math.round(scored.reduce((sum,item)=>sum+Number(item.exam_score)/Number(item.exam_max_score)*100,0)/scored.length*10)/10:null;

  return <div className="correction-history-backdrop" role="presentation" onMouseDown={e=>{if(e.currentTarget===e.target)onClose()}}>
    <section className="correction-history-modal" role="dialog" aria-modal="true" aria-label={`${student.studentName} 첨삭 기록`}>
      <header>
        <div><p className="eyebrow">교직원 전용 · 누적 첨삭 기록</p><h2>{student.studentName}</h2><span>{[student.school,student.grade].filter(Boolean).join(" · ")||"학생 정보"}</span></div>
        <button type="button" className="modal-close" aria-label="닫기" onClick={onClose}>×</button>
      </header>
      <div className="correction-history-summary">
        <div><small>누적 기록</small><b>{visible.length}<em>회</em></b></div>
        <div><small>시험 기록</small><b>{scored.length}<em>회</em></b></div>
        <div><small>시험 평균</small><b>{average==null?"—":average}<em>{average==null?"":"점"}</em></b></div>
      </div>
      <nav className="correction-history-filter" aria-label="과목 필터">{subjects.map(value=><button type="button" key={value} className={subject===value?"active":""} onClick={()=>setSubject(value)}>{value}</button>)}</nav>
      <div className="correction-history-list">
        {loading?<p className="correction-history-empty">첨삭 기록을 불러오는 중이에요…</p>:error?<p className="correction-history-error">{error}</p>:!visible.length?<p className="correction-history-empty">저장된 첨삭 기록이 없습니다.</p>:visible.map(item=>{
          const max=item.exam_max_score??100;
          const converted=item.exam_score==null||Number(max)<=0?null:Math.round(Number(item.exam_score)/Number(max)*1000)/10;
          return <article key={item.id}>
            <header><div><time>{formatDate(item.correction_date)}</time><span>{item.subject} 첨삭 · {item.start_time.slice(0,5)}–{item.end_time.slice(0,5)}</span></div><strong className={item.attendance_status}>{attendanceLabel[item.attendance_status]??item.attendance_status}{item.attendance_status==="late"&&item.late_minutes?` ${item.late_minutes}분`:""}</strong></header>
            <div className="correction-history-meta"><span>첨삭 담당</span><b>{item.recorded_by_name||"기록 없음"}</b></div>
            {item.exam_title?<section className="correction-history-block exam"><small>시험 기록</small><h3>{item.exam_title}</h3><p>{[cleanRange(item.exam_range),item.exam_score==null?null:`${formatScore(item.exam_score)} / ${formatScore(max)}점${converted==null?"":` · 환산 ${converted}점`}`,item.evaluation].filter(Boolean).join(" · ")}</p></section>:null}
            {item.correction_content?<section className="correction-history-block task"><small>오늘 한 첨삭과제</small><p>{item.correction_content}</p></section>:null}
            {!item.exam_title&&!item.correction_content?<p className="correction-history-no-detail">출결만 기록된 첨삭입니다.</p>:null}
          </article>
        })}
      </div>
    </section>
  </div>;
}

function cleanRange(value:string|null){return (value??"").replace(/^\[종류\][^\n]*\n?/,"").trim()}
function formatDate(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",year:"numeric",month:"long",day:"numeric",weekday:"short"}).format(new Date(`${value}T12:00:00+09:00`))}
function formatScore(value:number){return Number.isInteger(Number(value))?String(Number(value)):Number(value).toFixed(1)}
