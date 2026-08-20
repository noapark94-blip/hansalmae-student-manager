"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { FormEvent } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type Student={id:string;name:string;school:string|null;grade:string|null};
type Staff={id:string;name:string};
type Assignment={id:string;studentId:string;studentName:string;school:string|null;grade:string|null;subject:"국어"|"영어"|"수학";weekday:number;startTime:string;endTime:string;tutorId:string|null;tutorName:string|null;supervisorId:string|null;supervisorName:string|null;note:string|null};
type Exception={id:string;assignmentId:string;originalDate:string;kind:"move"|"cancel"|"extra";targetDate:string|null;targetStartTime:string|null;targetEndTime:string|null;note:string|null};
type Board={weekStart:string;students:Student[];staff:Staff[];assignments:Assignment[];exceptions:Exception[]};
type Occurrence={key:string;assignment:Assignment;date:string;startTime:string;endTime:string;state:"fixed"|"moved"|"extra";exception?:Exception};
type EditorState={row?:Assignment;weekday?:number;slot?:string}|null;

const days=["월","화","수","목","금","토","일"];
const weekdaySlots=[["14:30","16:00"],["16:00","17:30"],["17:30","19:00"],["19:00","20:30"],["20:30","22:00"]] as const;
const weekendSlots=[["09:30","11:00"],["11:00","12:30"],["12:30","14:00"],["14:00","15:30"],["15:30","17:00"]] as const;

export function CorrectionManagementBoard({supabase}:{supabase:SupabaseClient}){
  const[anchor,setAnchor]=useState(koreaToday());
  const[data,setData]=useState<Board|null>(null);
  const[loading,setLoading]=useState(true);
  const[error,setError]=useState("");
  const[editor,setEditor]=useState<EditorState>(null);
  const[action,setAction]=useState<{assignment:Assignment;date:string}|null>(null);
  const[selectedDay,setSelectedDay]=useState(1);

  const load=useCallback(async()=>{
    setLoading(true);
    setError("");
    const{data:next,error:loadError}=await supabase.rpc("correction_management_board_v2",{p_anchor:anchor});
    if(loadError){setError(`첨삭 시간표를 불러오지 못했습니다. ${loadError.message}`);setData(null);}
    else setData(next as Board);
    setLoading(false);
  },[anchor,supabase]);

  useEffect(()=>{void load();},[load]);
  const occurrences=useMemo(()=>buildOccurrences(data),[data]);
  const movedFrom=useMemo(()=>new Map((data?.exceptions??[]).filter(item=>item.kind==="move"||item.kind==="cancel").map(item=>[`${item.assignmentId}-${item.originalDate}`,item])),[data]);
  const changeWeek=(delta:number)=>setAnchor(current=>addDays(current,delta));

  return <>
    <div className="page-heading correction-heading">
      <div><p className="eyebrow">한살매 첨삭 운영</p><h1>첨삭 관리</h1><p>고정 첨삭일은 유지하고, 이번 주 변경·취소·추가만 예외 일정으로 관리합니다.</p></div>
      <button className="primary" onClick={()=>setEditor({})}>＋ 학생 추가</button>
    </div>
    <div className="correction-week-toolbar"><button onClick={()=>changeWeek(-7)}>‹ 이전 주</button><strong>{data?formatWeek(data.weekStart):"주간 시간표"}</strong><button onClick={()=>changeWeek(7)}>다음 주 ›</button><button className="today" onClick={()=>setAnchor(koreaToday())}>이번 주</button></div>
    {error&&<p className="attendance-error">{error}</p>}
    <nav className="correction-mobile-days">{days.map((day,index)=><button key={day} className={selectedDay===index+1?"active":""} onClick={()=>setSelectedDay(index+1)}>{day}</button>)}</nav>
    {loading?<section className="panel correction-empty">첨삭 시간표를 불러오는 중이에요…</section>:!data?<section className="panel correction-empty">첨삭 시간표를 표시할 수 없습니다.</section>:<section className="correction-week-board">{days.map((day,index)=>{
      const weekday=index+1;
      const date=addDays(data.weekStart,index);
      const slots=weekday<=5?weekdaySlots:weekendSlots;
      return <section key={day} className={`correction-day ${selectedDay===weekday?"mobile-active":""}`}>
        <header><span><b>{day}요일</b><small>{formatShortDate(date)}</small></span><em>{occurrences.filter(item=>item.date===date).length}명</em></header>
        <div className="correction-slot-list">{slots.map(([start,end])=>{
          const inSlot=occurrences.filter(item=>item.date===date&&item.startTime.slice(0,5)===start);
          const fixedMoved=(data.assignments??[]).filter(item=>item.weekday===weekday&&item.startTime.slice(0,5)===start).map(item=>({item,exception:movedFrom.get(`${item.id}-${date}`)})).filter(row=>row.exception);
          return <article className="correction-slot correction-slot-clickable" key={start} role="button" tabIndex={0} aria-label={`${day}요일 ${start} 학생 추가`} onClick={()=>setEditor({weekday,slot:start})} onKeyDown={event=>{if(event.key==="Enter"||event.key===" "){event.preventDefault();setEditor({weekday,slot:start});}}}>
            <div className="correction-slot-time"><b>{start}</b><span>– {end}</span></div>
            <div className="correction-slot-content">
              {(inSlot.length||fixedMoved.length)?<div className="correction-slot-students" onClick={event=>event.stopPropagation()}>
                {inSlot.map(row=><button key={row.key} className={`correction-student ${row.state}`} onClick={event=>{event.stopPropagation();setAction({assignment:row.assignment,date:row.state==="moved"&&row.exception?row.exception.originalDate:date});}}><span><b>{row.assignment.studentName}</b><small>{[row.assignment.grade,row.assignment.subject].filter(Boolean).join(" · ")}</small></span>{row.state!=="fixed"&&<em>{row.state==="moved"?"변경":"추가"}</em>}</button>)}
                {fixedMoved.map(row=><button key={`ghost-${row.item.id}`} className="correction-student ghost" onClick={event=>{event.stopPropagation();setAction({assignment:row.item,date});}}><span><b>{row.item.studentName}</b><small>{[row.item.grade,row.item.subject].filter(Boolean).join(" · ")}</small></span><em>{row.exception?.kind==="cancel"?"취소":"이동"}</em></button>)}
              </div>:<p className="correction-slot-empty">＋ 눌러서 학생 추가</p>}
              {(inSlot.length||fixedMoved.length)?<button type="button" className="correction-slot-add" onClick={event=>{event.stopPropagation();setEditor({weekday,slot:start});}}>＋ 학생 추가</button>:null}
            </div>
          </article>;
        })}</div>
      </section>;
    })}</section>}
    {editor&&data?<AssignmentEditor row={editor.row} initialWeekday={editor.weekday} initialSlot={editor.slot} data={data} supabase={supabase} onClose={()=>setEditor(null)} onSaved={async()=>{setEditor(null);await load();}}/>:null}
    {action&&data?<ScheduleActionModal assignment={action.assignment} originalDate={action.date} supabase={supabase} onEdit={()=>{setEditor({row:action.assignment});setAction(null);}} onClose={()=>setAction(null)} onSaved={async()=>{setAction(null);await load();}}/>:null}
  </>;
}

function AssignmentEditor({row,initialWeekday,initialSlot,data,supabase,onClose,onSaved}:{row?:Assignment;initialWeekday?:number;initialSlot?:string;data:Board;supabase:SupabaseClient;onClose:()=>void;onSaved:()=>Promise<void>}){
  const[studentId,setStudentId]=useState(row?.studentId??data.students[0]?.id??"");
  const[subject,setSubject]=useState<"국어"|"영어"|"수학">(row?.subject??"영어");
  const[weekday,setWeekday]=useState(row?.weekday??initialWeekday??1);
  const initial=findSlot(row?.weekday??initialWeekday??1,row?.startTime?.slice(0,5)??initialSlot);
  const[slot,setSlot]=useState<string>(initial);
  const[tutorId,setTutorId]=useState(row?.tutorId??"");
  const[supervisorId,setSupervisorId]=useState(row?.supervisorId??"");
  const[note,setNote]=useState(row?.note??"");
  const[saving,setSaving]=useState(false);
  const[error,setError]=useState("");
  const slots=weekday<=5?weekdaySlots:weekendSlots;

  useEffect(()=>{if(!slots.some(item=>item[0]===slot))setSlot(slots[0][0]);},[slot,slots]);

  const submit=async(event:FormEvent)=>{
    event.preventDefault();setSaving(true);setError("");
    const picked=slots.find(item=>item[0]===slot)??slots[0];
    const{error:saveError}=await supabase.rpc("staff_save_correction_assignment",{p_id:row?.id??null,p_student_id:studentId,p_subject:subject,p_weekday:weekday,p_start_time:picked[0],p_end_time:picked[1],p_tutor_profile_id:tutorId||null,p_supervisor_profile_id:supervisorId||null,p_note:note||null});
    if(saveError){setError(saveError.message.includes("duplicate")?"이미 같은 학생의 같은 과목 첨삭이 이 시간에 배정되어 있습니다.":saveError.message);setSaving(false);}else await onSaved();
  };
  const remove=async()=>{
    if(!row||!confirm(`${row.studentName} 학생의 ${row.subject} 고정 첨삭 배정을 삭제할까요?`))return;
    setSaving(true);
    const{error:removeError}=await supabase.rpc("staff_delete_correction_assignment",{p_id:row.id});
    if(removeError){setError(removeError.message);setSaving(false);}else await onSaved();
  };

  return <div className="modal-backdrop"><section className="student-modal correction-editor"><header><div><p className="eyebrow">고정 첨삭 일정</p><h2>{row?"첨삭 배정 수정":"학생 첨삭 배정"}</h2><span>{row?"기본 일정은 매주 반복됩니다. 특정 주 변경은 별도 예외 일정으로 처리합니다.":`${days[weekday-1]}요일 ${slot} 시간에 학생을 추가합니다.`}</span></div><button onClick={onClose}>×</button></header><form onSubmit={submit}><div className="form-grid"><label>학생<select required value={studentId} onChange={e=>setStudentId(e.target.value)}>{data.students.map(item=><option key={item.id} value={item.id}>{item.name} · {[item.school,item.grade].filter(Boolean).join(" ")}</option>)}</select></label><label>첨삭 과목<select value={subject} onChange={e=>setSubject(e.target.value as "국어"|"영어"|"수학")}><option>국어</option><option>영어</option><option>수학</option></select></label><label>요일<select value={weekday} onChange={e=>setWeekday(Number(e.target.value))}>{days.map((day,index)=><option key={day} value={index+1}>{day}요일</option>)}</select></label><label>시간<select value={slot} onChange={e=>setSlot(e.target.value)}>{slots.map(([start,end])=><option value={start} key={start}>{start}–{end}</option>)}</select></label><label>첨삭 담당<select value={tutorId} onChange={e=>setTutorId(e.target.value)}><option value="">미정</option>{data.staff.map(item=><option key={item.id} value={item.id}>{item.name}</option>)}</select></label><label>감독 선생님<select value={supervisorId} onChange={e=>setSupervisorId(e.target.value)}><option value="">미정</option>{data.staff.map(item=><option key={item.id} value={item.id}>{item.name}</option>)}</select></label><label className="full">특이사항<input value={note} onChange={e=>setNote(e.target.value)} placeholder="예: 주간 테스트 · 내신 과제 확인"/></label></div>{error&&<p className="form-error">{error}</p>}<footer>{row?<button type="button" className="danger-link" onClick={()=>void remove()}>고정 배정 삭제</button>:<span/>}<span><button type="button" className="secondary-button" onClick={onClose}>취소</button><button className="primary" disabled={saving||!studentId}>{saving?"저장 중…":"학생 추가"}</button></span></footer></form></section></div>;
}

function ScheduleActionModal({assignment,originalDate,supabase,onEdit,onClose,onSaved}:{assignment:Assignment;originalDate:string;supabase:SupabaseClient;onEdit:()=>void;onClose:()=>void;onSaved:()=>Promise<void>}){
  const[mode,setMode]=useState<"move"|"cancel"|"extra">("move");
  const[targetDate,setTargetDate]=useState(originalDate);
  const[targetStart,setTargetStart]=useState(assignment.startTime.slice(0,5));
  const[note,setNote]=useState("");
  const[saving,setSaving]=useState(false);
  const[error,setError]=useState("");
  const weekday=isoWeekday(targetDate);
  const slots=weekday<=5?weekdaySlots:weekendSlots;
  const picked=slots.find(item=>item[0]===targetStart)??slots[0];
  useEffect(()=>{if(!slots.some(item=>item[0]===targetStart))setTargetStart(slots[0][0]);},[slots,targetStart]);
  const submit=async()=>{setSaving(true);setError("");const{error:saveError}=await supabase.rpc("staff_save_correction_exception",{p_id:null,p_assignment_id:assignment.id,p_original_date:originalDate,p_kind:mode,p_target_date:mode==="cancel"?null:targetDate,p_target_start_time:mode==="cancel"?null:picked[0],p_target_end_time:mode==="cancel"?null:picked[1],p_note:note||null});if(saveError){setError(saveError.message.includes("duplicate")?"이 학생은 이번 주에 이미 변경 또는 취소 처리가 되어 있습니다.":saveError.message);setSaving(false);}else await onSaved();};
  return <div className="modal-backdrop"><section className="student-modal correction-action"><header><div><p className="eyebrow">이번 주만 변경</p><h2>{assignment.studentName} · {assignment.subject} 첨삭</h2><span>고정 일정 {days[assignment.weekday-1]} {assignment.startTime.slice(0,5)}–{assignment.endTime.slice(0,5)}은 그대로 유지됩니다.</span></div><button onClick={onClose}>×</button></header><div className="correction-action-types"><button className={mode==="move"?"active":""} onClick={()=>setMode("move")}>이번 주 시간 변경</button><button className={mode==="cancel"?"active":""} onClick={()=>setMode("cancel")}>이번 주 취소</button><button className={mode==="extra"?"active":""} onClick={()=>setMode("extra")}>추가 첨삭</button></div>{mode!=="cancel"&&<div className="form-grid correction-action-fields"><label>{mode==="move"?"변경 날짜":"추가 날짜"}<input type="date" value={targetDate} onChange={e=>setTargetDate(e.target.value)}/></label><label>시간<select value={targetStart} onChange={e=>setTargetStart(e.target.value)}>{slots.map(([start,end])=><option key={start} value={start}>{start}–{end}</option>)}</select></label></div>}<label className="correction-action-note">사유·메모<input value={note} onChange={e=>setNote(e.target.value)} placeholder="예: 병원 일정으로 수요일로 변경"/></label>{error&&<p className="form-error">{error}</p>}<footer><button className="secondary-button" onClick={onEdit}>고정 일정 수정</button><span><button className="secondary-button" onClick={onClose}>닫기</button><button className="primary" disabled={saving} onClick={()=>void submit()}>{saving?"저장 중…":"적용"}</button></span></footer></section></div>;
}

function buildOccurrences(data:Board|null):Occurrence[]{if(!data)return[];const result:Occurrence[]=[];for(const a of data.assignments??[]){const date=addDays(data.weekStart,a.weekday-1);const x=(data.exceptions??[]).find(e=>e.assignmentId===a.id&&e.originalDate===date&&(e.kind==="move"||e.kind==="cancel"));if(!x)result.push({key:`fixed-${a.id}-${date}`,assignment:a,date,startTime:a.startTime,endTime:a.endTime,state:"fixed"});else if(x.kind==="move"&&x.targetDate&&x.targetStartTime&&x.targetEndTime)result.push({key:`move-${x.id}`,assignment:a,date:x.targetDate,startTime:x.targetStartTime,endTime:x.targetEndTime,state:"moved",exception:x});}for(const x of data.exceptions??[]){if(x.kind!=="extra"||!x.targetDate||!x.targetStartTime||!x.targetEndTime)continue;const a=(data.assignments??[]).find(v=>v.id===x.assignmentId);if(a)result.push({key:`extra-${x.id}`,assignment:a,date:x.targetDate,startTime:x.targetStartTime,endTime:x.targetEndTime,state:"extra",exception:x});}return result}
function findSlot(weekday:number,start?:string){const slots=weekday<=5?weekdaySlots:weekendSlots;return slots.find(item=>item[0]===start)?.[0]??slots[0][0]}
function addDays(value:string,delta:number){const d=new Date(`${value}T12:00:00+09:00`);d.setUTCDate(d.getUTCDate()+delta);return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(d)}
function isoWeekday(value:string){const d=new Date(`${value}T12:00:00+09:00`);const day=d.getUTCDay();return day===0?7:day}
function koreaToday(){return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date())}
function formatShortDate(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"numeric",day:"numeric"}).format(new Date(`${value}T12:00:00+09:00`))}
function formatWeek(value:string){return `${formatShortDate(value)} – ${formatShortDate(addDays(value,6))}`}
function formatDayTime(date?:string|null,time?:string|null){if(!date)return"변경";return `${days[isoWeekday(date)-1]} ${time?.slice(0,5)??""}`}
