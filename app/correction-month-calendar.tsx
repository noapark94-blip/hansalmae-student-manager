"use client";

import { useCallback,useEffect,useMemo,useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type Assignment={id:string;studentId:string;studentName:string;school:string|null;grade:string|null;subject:"국어"|"영어"|"수학";weekday:number;startTime:string;endTime:string;validFrom:string;validUntil:string|null;tutorName:string|null;supervisorName:string|null;note:string|null;isDateOverride?:boolean};
type Exception={id:string;assignmentId:string;originalDate:string;kind:"move"|"cancel"|"extra";targetDate:string|null;targetStartTime:string|null;targetEndTime:string|null;note:string|null};
type Board={assignments:Assignment[];exceptions:Exception[]};
type Occurrence={assignment:Assignment;date:string;startTime:string;endTime:string};
type ReportRow={assignment_id:string;correction_date:string;start_time:string;attendance_status:string};
const weekdays=["월","화","수","목","금","토","일"];

export function CorrectionMonthCalendar({supabase,anchor,onSelect,onClose}:{supabase:SupabaseClient;anchor:string;onSelect:(date:string)=>void;onClose:()=>void}){
  const[month,setMonth]=useState(anchor.slice(0,7)+"-01");
  const[assignments,setAssignments]=useState<Assignment[]>([]);
  const[exceptions,setExceptions]=useState<Exception[]>([]);
  const[reports,setReports]=useState<Record<string,string>>({});
  const[loading,setLoading]=useState(true);
  const[error,setError]=useState("");
  const days=useMemo(()=>calendarDays(month),[month]);
  const load=useCallback(async()=>{
    setLoading(true);setError("");
    const anchors=Array.from(new Set(days.map(d=>weekOf(d)[0])));
    const boards=await Promise.all(anchors.map(p_anchor=>supabase.rpc("correction_management_board",{p_anchor})));
    const failed=boards.find(x=>x.error);if(failed?.error){setError("첨삭 캘린더를 불러오지 못했습니다.");setLoading(false);return}
    const parsed=boards.map(x=>x.data as Board);
    const assignmentMap=new Map<string,Assignment>();for(const b of parsed)for(const a of b.assignments??[])assignmentMap.set(a.id,a);setAssignments([...assignmentMap.values()]);
    const exMap=new Map<string,Exception>();for(const b of parsed)for(const e of b.exceptions??[])exMap.set(e.id,e);setExceptions([...exMap.values()]);
    const start=days[0],end=days[days.length-1];
    const result=await supabase.from("correction_reports").select("assignment_id,correction_date,start_time,attendance_status").gte("correction_date",start).lte("correction_date",end);
    const next:Record<string,string>={};if(!result.error)for(const r of (result.data??[]) as ReportRow[])next[`${r.assignment_id}-${r.correction_date}-${String(r.start_time).slice(0,5)}`]=r.attendance_status;setReports(next);
    setLoading(false);
  },[days,supabase]);
  useEffect(()=>{void load()},[load]);
  const changeMonth=(delta:number)=>{const d=new Date(`${month}T12:00:00+09:00`);d.setUTCMonth(d.getUTCMonth()+delta);setMonth(formatDate(d).slice(0,7)+"-01")};
  return <div className="modal-backdrop" onMouseDown={e=>{if(e.target===e.currentTarget)onClose()}}><section className="student-modal correction-month-modal"><header><div><p className="eyebrow">첨삭 출결</p><h2>전체 첨삭 캘린더</h2><span>월간 첨삭 예정과 출석·지각·결석 기록을 한눈에 확인합니다.</span></div><button type="button" onClick={onClose}>×</button></header><div className="correction-month-toolbar"><button type="button" onClick={()=>changeMonth(-1)}>‹</button><strong>{formatMonth(month)}</strong><button type="button" onClick={()=>changeMonth(1)}>›</button><button type="button" onClick={()=>setMonth(koreaToday().slice(0,7)+"-01")}>이번 달</button></div>{error?<p className="form-error">{error}</p>:null}{loading?<p className="correction-month-loading">캘린더를 불러오는 중이에요…</p>:<><div className="correction-month-weekdays">{weekdays.map(x=><b key={x}>{x}</b>)}</div><div className="correction-month-grid">{days.map(day=>{const inMonth=day.slice(0,7)===month.slice(0,7);const rows=buildOccurrences(assignments,exceptions,day);return <button type="button" key={day} className={`${inMonth?"":"outside"} ${day===anchor?"selected":""} ${day===koreaToday()?"today":""}`} onClick={()=>{onSelect(day);onClose()}}><span>{+day.slice(8)}</span><div>{rows.slice(0,4).map(row=>{const status=reports[`${row.assignment.id}-${day}-${row.startTime.slice(0,5)}`]??"scheduled";return <em key={`${row.assignment.id}-${row.startTime}`} className={`${status} ${row.assignment.isDateOverride?"date-override":""}`}>{row.assignment.studentName}{row.assignment.isDateOverride?<span className="correction-date-override-badge compact">보정</span>:null}</em>})}{rows.length>4?<small>+{rows.length-4}명</small>:null}{!rows.length?<small className="empty">첨삭 없음</small>:null}</div></button>})}</div></>}</section></div>;
}
function buildOccurrences(assignments:Assignment[],exceptions:Exception[],date:string):Occurrence[]{const weekday=isoWeekday(date);const rows:Occurrence[]=[];for(const a of assignments){if(a.weekday===weekday&&isAssignmentValid(a,date)){const x=exceptions.find(e=>e.assignmentId===a.id&&e.originalDate===date&&(e.kind==="move"||e.kind==="cancel"));if(!x)rows.push({assignment:a,date,startTime:a.startTime,endTime:a.endTime})}}for(const x of exceptions){if((x.kind==="move"||x.kind==="extra")&&x.targetDate===date&&x.targetStartTime&&x.targetEndTime){const a=assignments.find(v=>v.id===x.assignmentId);if(a)rows.push({assignment:a,date,startTime:x.targetStartTime,endTime:x.targetEndTime})}}return rows.sort((a,b)=>a.startTime.localeCompare(b.startTime)||a.assignment.studentName.localeCompare(b.assignment.studentName,"ko"))}
function isAssignmentValid(assignment:Assignment,date:string){return assignment.validFrom<=date&&(!assignment.validUntil||assignment.validUntil>=date)}
function calendarDays(month:string){const first=new Date(`${month}T12:00:00+09:00`);const firstIso=isoWeekday(formatDate(first));const start=addDays(formatDate(first),1-firstIso);const last=new Date(first);last.setUTCMonth(last.getUTCMonth()+1);last.setUTCDate(0);const endIso=isoWeekday(formatDate(last));const end=addDays(formatDate(last),7-endIso);const out:string[]=[];for(let d=start;;d=addDays(d,1)){out.push(d);if(d===end)break}return out}
function isoWeekday(value:string){const d=new Date(`${value}T12:00:00+09:00`);const day=d.getUTCDay();return day===0?7:day}
function addDays(value:string,days:number){const d=new Date(`${value}T12:00:00+09:00`);d.setUTCDate(d.getUTCDate()+days);return formatDate(d)}
function weekOf(value:string){const weekday=isoWeekday(value);const monday=addDays(value,1-weekday);return Array.from({length:7},(_,i)=>addDays(monday,i))}
function formatDate(d:Date){return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(d)}
function formatMonth(v:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",year:"numeric",month:"long"}).format(new Date(`${v}T12:00:00+09:00`))}
function koreaToday(){return formatDate(new Date())}
