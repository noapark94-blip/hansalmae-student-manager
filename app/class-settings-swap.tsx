"use client";
import { useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { ClassScheduleSwap } from "./class-schedule-swap";
import type { SwapSchedule } from "./class-schedule-swap-model";
import styles from "./class-settings-swap.module.css";
const days = ["월", "화", "수", "목", "금", "토", "일"];
export function ClassSettingsSwap({supabase,classId,onCancel,onSaved,onBusyChange}:{supabase:SupabaseClient;classId:string;onCancel:()=>void;onSaved:()=>Promise<void>;onBusyChange:(value:boolean)=>void}) {
  const [rows,setRows]=useState<SwapSchedule[]>([]);
  const [sourceId,setSourceId]=useState("");
  const [loading,setLoading]=useState(true);
  const [error,setError]=useState("");
  const [attempt,setAttempt]=useState(0);
  const [busy,setBusy]=useState(false);
  useEffect(()=>{let active=true;const load=async()=>{setLoading(true);setError("");try{const {data,error:failure}=await supabase.rpc("staff_schedule_hub");if(failure)throw failure;if(!Array.isArray(data?.classSchedules))throw new Error("수업 시간을 불러오지 못했습니다.");if(active){setRows(data.classSchedules);setSourceId("");}}catch(e){if(active)setError((e as {message?:string}).message??"수업 시간을 불러오지 못했습니다.");}finally{if(active)setLoading(false);}};void load();return()=>{active=false;};},[supabase,classId,attempt]);
  const own=rows.filter(r=>r.classId===classId).sort((a,b)=>a.weekday-b.weekday||a.startTime.localeCompare(b.startTime));
  const selected=own.find(r=>r.id===sourceId);
  return <div className={styles.container}>
    <div className={styles.intro}><small>정규 시간표</small><h3>어느 요일의 시간을 바꿀까요?</h3><p>묶여 있는 요일도 하나씩 선택할 수 있어요.</p></div>
    {loading?<p role="status" className={styles.message}>저장된 수업 시간을 불러오는 중이에요.</p>:error?<p role="alert" className={styles.message}>{error} <button type="button" onClick={()=>setAttempt(n=>n+1)}>다시 시도</button></p>:<div className={styles.days} role="group" aria-label="맞바꿀 내 수업 요일">{own.map(r=><button type="button" key={r.id} aria-pressed={sourceId===r.id} disabled={busy} onClick={()=>setSourceId(r.id)}><b>{days[r.weekday-1]}요일</b><span>{r.startTime.slice(0,5)}–{r.endTime.slice(0,5)}</span></button>)}{!own.length&&<p className={styles.message}>저장된 수업 시간이 없습니다. 먼저 수업 요일·시간을 등록해 주세요.</p>}</div>}
    {selected?<div className={styles.content}><ClassScheduleSwap key={selected.id} supabase={supabase} row={selected} schedules={rows} onCancel={onCancel} onSaved={onSaved} onBusyChange={value=>{setBusy(value);onBusyChange(value);}}/></div>:<div className={styles.back}><button type="button" onClick={onCancel}>클래스 수정으로 돌아가기</button></div>}
  </div>;
}
