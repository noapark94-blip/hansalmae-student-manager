"use client";

import type { FormEvent } from "react";
import { useCallback, useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type Status="active"|"paused"|"completed";
type History={ id:string; previousStatus:Status; newStatus:Status; effectiveOn:string; returnExpectedOn:string|null; note:string|null; changedByName:string; createdAt:string };
const labels:Record<Status,string>={active:"재원",paused:"휴원",completed:"퇴원"};

export function StudentLifecyclePanel({supabase,studentId,status,onChanged}:{supabase:SupabaseClient;studentId:string;status:string;onChanged:(status:string)=>void}){
  const [history,setHistory]=useState<History[]>([]); const [loading,setLoading]=useState(true); const [target,setTarget]=useState<Status|null>(null); const [effectiveOn,setEffectiveOn]=useState(today()); const [returnExpectedOn,setReturnExpectedOn]=useState(""); const [note,setNote]=useState(""); const [saving,setSaving]=useState(false); const [error,setError]=useState(""); const current=normalizeStatus(status);
  const load=useCallback(async()=>{const{data,error:loadError}=await supabase.rpc("staff_student_lifecycle_history",{p_student_id:studentId});if(!loadError)setHistory((data??[]) as History[]);setLoading(false);},[studentId,supabase]);
  useEffect(()=>{void load();},[load]);
  const submit=async(event:FormEvent)=>{event.preventDefault();if(!target)return;setSaving(true);setError("");const{error:saveError}=await supabase.rpc("staff_set_student_lifecycle",{p_student_id:studentId,p_status:target,p_effective_on:effectiveOn,p_note:note||null,p_return_expected_on:target==="paused"?returnExpectedOn:null});if(saveError){setError(readError(saveError.message));setSaving(false);return;}onChanged(target);setTarget(null);setNote("");setReturnExpectedOn("");setEffectiveOn(today());await load();setSaving(false);};
  const choices=(["active","paused","completed"] as Status[]).filter((item)=>item!==current);
  return <section className="student-lifecycle"><header><div><h3>재원 상태·이력</h3><p>휴원·퇴원 시 현재 수강을 종료하고 과거 기록은 보존합니다.</p></div><span className={current}>{labels[current]}</span></header><div className="lifecycle-actions">{choices.map((item)=><button type="button" key={item} className={target===item?"selected":""} onClick={()=>{setTarget(item);setReturnExpectedOn("");setError("");}}>{item==="active"?"재원 복귀":item==="paused"?"휴원 처리":"퇴원 처리"}</button>)}</div>{target&&<form onSubmit={submit}><label>적용일<input required type="date" max={today()} value={effectiveOn} onChange={(event)=>setEffectiveOn(event.target.value)}/></label>{target==="paused"&&<label>복귀 예정일 <b>*</b><input required type="date" min={effectiveOn} value={returnExpectedOn} onChange={(event)=>setReturnExpectedOn(event.target.value)}/></label>}<label className="grow">처리 사유 {target!=="active"&&<b>*</b>}<input required={target!=="active"} value={note} onChange={(event)=>setNote(event.target.value)} placeholder={target==="active"?"예: 복귀 상담 완료":"예: 개인 사정"}/></label><button className="primary" disabled={saving}>{saving?"처리 중…":`${labels[target]} 확정`}</button>{error&&<p className="form-error">{error}</p>}</form>}<div className="lifecycle-history"><h4>변경 이력</h4>{loading?<p>이력을 불러오는 중이에요…</p>:history.length?history.map((item)=><article key={item.id}><time>{formatDate(item.effectiveOn)}</time><span><b>{labels[item.previousStatus]} → {labels[item.newStatus]}</b><small>{item.changedByName}{item.returnExpectedOn?` · 복귀 예정 ${formatDate(item.returnExpectedOn)}`:""}{item.note?` · ${item.note}`:""}</small></span></article>):<p>아직 상태 변경 이력이 없습니다.</p>}</div></section>;
}
function today(){return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date())}
function formatDate(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",year:"numeric",month:"short",day:"numeric"}).format(new Date(value))}
function readError(message:string){return ["교직원","학생","상태","사유","적용일","복귀","수강"].some((word)=>message.includes(word))?message:"재원 상태를 변경하지 못했습니다."}
function normalizeStatus(value:string):Status{return value==="active"||value==="재원"?"active":value==="paused"||value==="휴원"?"paused":"completed"}
