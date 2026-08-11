"use client";

import type { FormEvent } from "react";
import { useCallback, useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type MakeupStatus = "scheduled" | "completed" | "cancelled";
type Teacher = { id: string; name: string };
type MakeupItem = { attendanceId:string; studentId:string; studentName:string; className:string; missedDate:string; attendanceNote:string|null; sessionId:string|null; teacherId:string|null; teacherName:string|null; scheduledAt:string|null; endsAt:string|null; room:string|null; status:MakeupStatus|null; note:string|null };
type MakeupData = { isStaff:boolean; teachers:Teacher[]; items:MakeupItem[] };
type EditorValues = { teacherId:string; date:string; startTime:string; endTime:string; room:string; note:string };
const statusLabel:Record<MakeupStatus,string> = { scheduled:"예약", completed:"완료", cancelled:"취소" };

export function MakeupBoard({ supabase }: { supabase:SupabaseClient }) {
  const [data,setData] = useState<MakeupData>({ isStaff:false,teachers:[],items:[] });
  const [loading,setLoading] = useState(true); const [error,setError] = useState(""); const [editing,setEditing] = useState<MakeupItem|null>(null);
  const load = useCallback(async () => { setLoading(true); setError(""); const { data:next,error:loadError } = await supabase.rpc("makeup_board"); if (loadError) setError("보강 내역을 불러오지 못했습니다."); else setData(next as MakeupData); setLoading(false); },[supabase]);
  useEffect(() => { void load(); },[load]);
  const counts = useMemo(() => data.items.reduce((result,item) => { if (!item.status || item.status === "cancelled") result.waiting += 1; else result[item.status] += 1; return result; },{ waiting:0,scheduled:0,completed:0 }),[data.items]);
  const setStatus = async (item:MakeupItem,status:MakeupStatus) => { if (!item.sessionId || !confirm(status === "completed" ? `${item.studentName} 학생의 보강을 완료 처리할까요?` : `${item.studentName} 학생의 보강 예약을 취소할까요?`)) return; setError(""); const { error:saveError } = await supabase.rpc("staff_set_makeup_status",{ p_session_id:item.sessionId,p_status:status }); if (saveError) setError("보강 상태를 변경하지 못했습니다."); else await load(); };
  if (loading) return <section className="panel makeup-empty">보강 내역을 불러오는 중이에요…</section>;
  return <><div className="page-heading compact"><div><p className="eyebrow">결석 출결 연동</p><h1>{data.isStaff ? "보강 관리" : "보강 일정"}</h1><p>{data.isStaff ? "결석 학생의 보강을 예약하고 완료 여부를 관리합니다." : "예정된 보강 수업의 시간과 담당 선생님을 확인합니다."}</p></div></div>
    {error && <p className="attendance-error">{error}</p>}{data.isStaff && <div className="makeup-summary"><span>예약 대기 <b>{counts.waiting}</b></span><span>예약 <b>{counts.scheduled}</b></span><span>완료 <b>{counts.completed}</b></span></div>}
    <section className="panel makeup-panel">{data.items.length === 0 ? <p className="makeup-empty">{data.isStaff ? "현재 보강이 필요한 결석 기록이 없습니다." : "확인할 보강 일정이 없습니다."}</p> : <div className="makeup-list">{data.items.map((item) => <article key={item.attendanceId}>
      <div className="makeup-student"><i>{item.studentName.slice(0,1)}</i><span><b>{item.studentName}</b><small>{item.className} · {formatDate(item.missedDate)} 결석</small></span></div>
      <div className="makeup-time">{item.scheduledAt && item.endsAt ? <><b>{formatDateTime(item.scheduledAt)}</b><small>– {formatTime(item.endsAt)} · {item.room}</small></> : <><b>일정 미정</b><small>담당 선생님 배정 전</small></>}</div>
      <div className="makeup-teacher"><small>담당</small><b>{item.teacherName ?? "미정"}</b></div><span className={`makeup-status ${item.status ?? "waiting"}`}>{item.status ? statusLabel[item.status] : "대기"}</span>
      {data.isStaff && <div className="makeup-actions">{item.status !== "completed" && <button className="secondary-button" onClick={() => setEditing(item)}>{item.status === "scheduled" ? "일정 수정" : "예약하기"}</button>}{item.status === "scheduled" && <><button className="primary" onClick={() => void setStatus(item,"completed")}>완료</button><button className="danger-link" onClick={() => void setStatus(item,"cancelled")}>취소</button></>}</div>}{item.note && <p className="makeup-note">메모 · {item.note}</p>}
    </article>)}</div>}</section>{editing && <MakeupEditor item={editing} teachers={data.teachers} supabase={supabase} onClose={() => setEditing(null)} onSaved={async () => { setEditing(null); await load(); }} />}</>;
}

function MakeupEditor({ item,teachers,supabase,onClose,onSaved }: { item:MakeupItem; teachers:Teacher[]; supabase:SupabaseClient; onClose:()=>void; onSaved:()=>Promise<void> }) {
  const start = item.scheduledAt ? koreaParts(item.scheduledAt) : { date:koreaToday(),time:"17:30" }; const end = item.endsAt ? koreaParts(item.endsAt) : { date:start.date,time:"19:00" };
  const [values,setValues] = useState<EditorValues>({ teacherId:item.teacherId ?? teachers[0]?.id ?? "",date:start.date,startTime:start.time,endTime:end.time,room:item.room ?? "",note:item.note ?? "" }); const [saving,setSaving] = useState(false); const [error,setError] = useState("");
  const update = (field:keyof EditorValues,value:string) => setValues((current) => ({ ...current,[field]:value }));
  const submit = async (event:FormEvent<HTMLFormElement>) => { event.preventDefault(); setSaving(true); setError(""); const { error:saveError } = await supabase.rpc("staff_save_makeup",{ p_attendance_id:item.attendanceId,p_teacher_id:values.teacherId,p_date:values.date,p_start_time:values.startTime,p_end_time:values.endTime,p_room:values.room,p_note:values.note || null }); if (saveError) { setError(readSaveError(saveError.message)); setSaving(false); } else await onSaved(); };
  return <div className="modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><section className="student-modal schedule-editor" role="dialog" aria-modal="true"><header><div><p className="eyebrow">보강 일정 배정</p><h2>{item.studentName} 학생</h2><span>{item.className} · {formatDate(item.missedDate)} 결석</span></div><button type="button" aria-label="닫기" onClick={onClose}>×</button></header><form onSubmit={submit}>
    <label className="editor-field">담당 선생님<select required value={values.teacherId} onChange={(event) => update("teacherId",event.target.value)}><option value="">선택해 주세요</option>{teachers.map((teacher) => <option key={teacher.id} value={teacher.id}>{teacher.name}</option>)}</select></label>
    <div className="form-pair"><label className="editor-field">날짜<input required type="date" value={values.date} onChange={(event) => update("date",event.target.value)} /></label><label className="editor-field">시작<input required type="time" value={values.startTime} onChange={(event) => update("startTime",event.target.value)} /></label><label className="editor-field">종료<input required type="time" value={values.endTime} onChange={(event) => update("endTime",event.target.value)} /></label></div>
    <label className="editor-field">강의실<input required value={values.room} onChange={(event) => update("room",event.target.value)} placeholder="예: A 강의실" /></label><label className="editor-field">메모<input value={values.note} onChange={(event) => update("note",event.target.value)} placeholder="준비물, 보강 범위 등 (선택)" /></label>
    {error && <p className="form-error">{error}</p>}<footer><button type="button" className="secondary-button" onClick={onClose}>취소</button><button className="primary" disabled={saving || !values.teacherId}>{saving ? "저장 중…" : "보강 예약"}</button></footer>
  </form></section></div>;
}

function koreaParts(value:string) { const parts = new Intl.DateTimeFormat("en",{ timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit",hour:"2-digit",minute:"2-digit",hour12:false }).formatToParts(new Date(value)); const item = Object.fromEntries(parts.map((part) => [part.type,part.value])); return { date:`${item.year}-${item.month}-${item.day}`,time:`${item.hour === "24" ? "00" : item.hour}:${item.minute}` }; }
function koreaToday() { return koreaParts(new Date().toISOString()).date; }
function formatDate(value:string) { return new Intl.DateTimeFormat("ko-KR",{ timeZone:"Asia/Seoul",month:"long",day:"numeric",weekday:"short" }).format(new Date(`${value}T00:00:00+09:00`)); }
function formatDateTime(value:string) { return new Intl.DateTimeFormat("ko-KR",{ timeZone:"Asia/Seoul",month:"long",day:"numeric",weekday:"short",hour:"2-digit",minute:"2-digit",hour12:false }).format(new Date(value)); }
function formatTime(value:string) { return new Intl.DateTimeFormat("ko-KR",{ timeZone:"Asia/Seoul",hour:"2-digit",minute:"2-digit",hour12:false }).format(new Date(value)); }
function readSaveError(message:string) { return ["겹치는","늦어야","입력해","찾을 수","교직원","보강이 필요한"].some((word) => message.includes(word)) ? message : "보강 일정을 저장하지 못했습니다. 입력 내용을 확인해 주세요."; }
