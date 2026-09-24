"use client";
import {useState} from "react";
import type {SupabaseClient} from "@supabase/supabase-js";
import styles from "./academy-closures.module.css";
type Student={id:string;studentName:string;subject:string;startTime:string};
export function CorrectionClosureBanner({supabase,date,reason,students,onApplied}:{supabase:SupabaseClient;date:string;reason:string;students:Student[];onApplied:()=>Promise<void>}){
 const[selected,setSelected]=useState<Set<string>>(new Set()),[expanded,setExpanded]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState("");
 async function apply(){if(busy||!selected.size)return;setBusy(true);setError("");try{const{error}=await supabase.rpc("staff_open_correction_days",{p_assignments:[...selected],p_date:date});if(error)throw error;await onApplied();setSelected(new Set());setExpanded(false);}catch(e){setError((e as {message?:string}).message??"첨삭을 열지 못했습니다.");}finally{setBusy(false);}}
 return <section className={styles.section}><div className={styles.bar}><div><b>학원 휴강일 · {reason}</b><span>{students.length?`첨삭 ${students.length}명 휴강 · 결석·미작성 집계와 알림톡 대상에서 제외됩니다.`:"별도로 연 첨삭만 진행합니다."}</span></div>{students.length>0&&<button type="button" disabled={busy} onClick={()=>setExpanded(!expanded)}>{expanded?"접기":"오늘 첨삭 진행"}</button>}</div>{expanded&&<div className={styles.body}><p className={styles.intro}>오늘 실제로 첨삭을 진행할 학생을 선택해 주세요.</p><div className={styles.selection}>{students.map(s=><label key={s.id}><input type="checkbox" disabled={busy} checked={selected.has(s.id)} onChange={e=>setSelected(previous=>{const next=new Set(previous);if(e.target.checked)next.add(s.id);else next.delete(s.id);return next;})}/><b>{s.studentName}</b><span>{s.subject} · {s.startTime.slice(0,5)}</span></label>)}</div><button className="primary" type="button" disabled={busy||!selected.size} onClick={()=>void apply()}>{busy?"적용 중…":`선택한 ${selected.size}명 첨삭 진행`}</button>{error&&<p role="alert" className={styles.error}>{error}</p>}</div>}</section>;
}
