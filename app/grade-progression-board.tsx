"use client";

import { useCallback, useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { appConfirm } from "./app-dialog";

type ProgressionItem = { id:string; studentName:string; previousGrade:string; previousSchool:string|null; proposedGrade:string|null; proposedSchool:string|null; transitionKind:"automatic"|"school_change"|"graduation"|"repeat_year"; decision:string|null; approvalStatus:"automatic"|"pending"|"approved"; appliedAt:string|null };
type ProgressionBoard = { academicYear:number; available:boolean; prepared:boolean; earlyApplied:boolean; pendingCount:number; readyCount:number; items:ProgressionItem[]; schools:string[] };

const decisionOptions = {
  graduation: [["graduated","졸업"],["repeat","재수"],["withdrawn","퇴원"],["stay","재원 유지"]],
  repeat_year: [["repeat","재수 유지"],["withdrawn","퇴원"]],
} as const;

export function GradeProgressionBoard({ supabase, onChanged }: { supabase:SupabaseClient; onChanged?:()=>void }) {
  const [board,setBoard]=useState<ProgressionBoard|null>(null);
  const [busy,setBusy]=useState(false);
  const [error,setError]=useState("");
  const load=useCallback(async()=>{const {data,error}=await supabase.rpc("admin_grade_progression_board"); if(error)setError(error.message); else setBoard(data as ProgressionBoard);},[supabase]);
  useEffect(()=>{void load();},[load]);
  const prepare=async()=>{setBusy(true);setError("");const {error}=await supabase.rpc("prepare_grade_progression",{p_force:false});setBusy(false);if(error)setError(error.message);else await load();};
  const approve=async(item:ProgressionItem,decision:string,school?:string)=>{setBusy(true);setError("");const {error}=await supabase.rpc("admin_approve_grade_progression",{p_item_id:item.id,p_decision:decision,p_school:school||null});setBusy(false);if(error)setError(error.message);else await load();};
  const applyNow=async()=>{if(!board||!await appConfirm({eyebrow:"학년 정보 전환",title:`${board.academicYear}학년도 정보로 지금 전환할까요?`,notice:"적용 후에는 자동으로 되돌릴 수 없습니다. 승인 내용을 한 번 더 확인해 주세요.",confirmLabel:"지금 전환",tone:"danger"}))return;setBusy(true);setError("");const {error}=await supabase.rpc("admin_apply_grade_progression_now");setBusy(false);if(error)setError(error.message);else{await load();onChanged?.();}};
  if(!board)return <section className="grade-progression-card"><p>학년 전환 정보를 확인하는 중…</p></section>;
  const pending=board.items.filter(i=>i.approvalStatus==="pending"&&!i.appliedAt);
  return <section className="grade-progression-card">
    <header><div><span>다음 학년도 준비</span><h2>{board.academicYear}학년도 학년 전환</h2><p>1월 1일 자동 전환 · 11월부터 반편성과 조기 전환 가능</p></div><b className={board.pendingCount?"attention":""}>{board.pendingCount?`승인 대기 ${board.pendingCount}명`:board.prepared?"준비 완료":"준비 전"}</b></header>
    {!board.available&&!board.prepared&&<div className="grade-progression-guide"><strong>11월 1일부터 준비할 수 있어요</strong><span>현재 학년은 유지되고 다음 학년도 학년으로 미리 반편성할 수 있습니다.</span></div>}
    {board.available&&!board.prepared&&<button className="grade-primary" disabled={busy} onClick={()=>void prepare()}>다음 학년도 준비</button>}
    {board.prepared&&<>
      <div className="grade-progression-summary"><span><small>자동·승인 완료</small><b>{board.readyCount}명</b></span><span><small>승인 필요</small><b>{board.pendingCount}명</b></span><span><small>전환 완료</small><b>{board.items.filter(i=>i.appliedAt).length}명</b></span></div>
      {!!pending.length&&<div className="grade-approval-list">{pending.map(item=><GradeApproval key={item.id} item={item} schools={board.schools} busy={busy} onApprove={approve}/>)}</div>}
      <div className="grade-progression-actions"><button className="grade-primary" disabled={busy||board.pendingCount>0||board.readyCount===0} onClick={()=>void applyNow()}>지금 새 학년으로 전환</button><small>{board.pendingCount>0?"승인 대기 학생을 모두 처리하면 사용할 수 있습니다.":"누르지 않아도 1월 1일에 자동으로 전환됩니다."}</small></div>
    </>}
    {error&&<p className="form-error">{error}</p>}
  </section>;
}

function GradeApproval({item,schools,busy,onApprove}:{item:ProgressionItem;schools:string[];busy:boolean;onApprove:(item:ProgressionItem,decision:string,school?:string)=>Promise<void>}){
  const [choice,setChoice]=useState("");
  const schoolChange=item.transitionKind==="school_change";
  const options=schoolChange?[]:decisionOptions[item.transitionKind as "graduation"|"repeat_year"];
  return <article><div><b>{item.studentName}</b><span>{item.previousSchool?`${item.previousSchool} · `:""}{item.previousGrade}</span></div>{schoolChange?<select value={choice} onChange={e=>setChoice(e.target.value)}><option value="">진학 학교 선택</option>{schools.map(s=><option key={s} value={s}>{s}</option>)}</select>:<select value={choice} onChange={e=>setChoice(e.target.value)}><option value="">처리 선택</option>{options.map(([value,label])=><option key={value} value={value}>{label}</option>)}</select>}<button disabled={busy||!choice} onClick={()=>void onApprove(item,schoolChange?"school_change":choice,schoolChange?choice:undefined)}>승인</button></article>;
}
