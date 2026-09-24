"use client";
import {useCallback,useEffect,useRef,useState} from "react";
import type {SupabaseClient} from "@supabase/supabase-js";
import {useStaffLiveUpdates} from "./use-staff-live-updates";
import {appConfirm} from "./app-dialog";
import styles from "./academy-closures.module.css";
export type AcademyClosure={id:string;startsOn:string;endsOn:string;reason:string;regular:boolean;correction:boolean;version:string};
export function AcademyClosures({supabase,year,date,canManage,onChange}:{supabase:SupabaseClient;year:number;date:string;canManage:boolean;onChange:(rows:AcademyClosure[])=>void}){
 const[rows,setRows]=useState<AcademyClosure[]>([]),[open,setOpen]=useState(false),[busy,setBusy]=useState(false),[error,setError]=useState("");
 const[editing,setEditing]=useState<AcademyClosure|null>(null),[from,setFrom]=useState(date),[to,setTo]=useState(date),[reason,setReason]=useState(""),[regular,setRegular]=useState(true),[correction,setCorrection]=useState(true);
 const dialog=useRef<HTMLDialogElement>(null);
 const load=useCallback(async()=>{const{data,error}=await supabase.rpc("staff_academy_closures",{p_from:`${year}-01-01`,p_to:`${year}-12-31`});if(error){setError(error.message);return;}setRows(data??[]);onChange(data??[]);},[supabase,year,onChange]);
 useStaffLiveUpdates(supabase,`academy-closures-${year}`,"key=eq.academy-closures",async()=>{await load();},failure=>setError((failure as {message?:string}).message??"휴강 설정을 갱신하지 못했습니다."),true);
 useEffect(()=>{if(open)dialog.current?.showModal();else dialog.current?.close();},[open]);
 const reset=()=>{setEditing(null);setFrom(date);setTo(date);setReason("");setRegular(true);setCorrection(true);setError("");};
 const edit=(r:AcademyClosure)=>{setEditing(r);setFrom(r.startsOn);setTo(r.endsOn);setReason(r.reason);setRegular(r.regular);setCorrection(r.correction);setError("");};
 async function confirm(options:Parameters<typeof appConfirm>[0]){dialog.current?.close();try{return await appConfirm(options);}finally{dialog.current?.showModal();}}
 async function save(remove=false){if(busy)return;setBusy(true);setError("");try{
  const args={p_id:editing?.id??null,p_from:from,p_to:to,p_reason:reason.trim(),p_regular:regular,p_correction:correction,p_version:editing?.version??null,p_confirm:false,p_delete:remove};
  if(remove&&!await confirm({eyebrow:"학원 휴강",title:"이 휴강 일정을 취소할까요?",copy:"다른 휴강 일정이 없는 날짜는 원래 시간표대로 돌아갑니다. 기존 기록은 유지됩니다.",confirmLabel:"휴강 취소",tone:"danger"}))return;
  if(!remove){const preview=await supabase.rpc("admin_save_academy_closure",args);if(preview.error)throw preview.error;
   const count=preview.data.regularRecords+preview.data.correctionRecords;
   if(!await confirm({eyebrow:"학원 휴강",title:editing?"휴강 설정을 변경할까요?":"학원 휴강을 등록할까요?",copy:`${from} ~ ${to} · ${reason.trim()}`,notice:count?`이미 저장한 정규수업 ${preview.data.regularRecords}건·첨삭 ${preview.data.correctionRecords}건은 진행 상태와 기록을 유지합니다. 나머지 대상만 휴강 처리됩니다.`:"정규수업·첨삭 중 선택한 대상은 기본 휴강 처리됩니다. 결석·미작성 집계와 수업 알림톡 대상에서 제외되며, 휴강 안내 메시지는 자동 발송되지 않습니다.",confirmLabel:count?"기존 기록 유지하고 적용":"휴강 적용"}))return;
  }
  const result=await supabase.rpc("admin_save_academy_closure",{...args,p_confirm:true});if(result.error)throw result.error;await load();reset();window.dispatchEvent(new Event("hansalmae-correction-assignments-changed"));
 }catch(e){setError((e as {message?:string}).message??"휴강 설정을 저장하지 못했습니다.");}finally{setBusy(false);}}
 const today=rows.filter(r=>r.startsOn<=date&&r.endsOn>=date);
 return <section className={styles.section} aria-label="학원 휴강 관리"><div className={styles.bar}><div><b>학원 휴강</b><span>{today.length?today.map(r=>`${r.reason} · ${[r.regular&&"정규수업",r.correction&&"첨삭"].filter(Boolean).join("·")}`).join(" / "):"선택한 날짜는 정상 운영일입니다."}</span></div>{canManage&&<button type="button" onClick={()=>{reset();setOpen(true);}}>휴강 관리</button>}</div>{error&&!open&&<p role="alert">{error}</p>}
 <dialog className={styles.dialog} ref={dialog} onCancel={e=>{e.preventDefault();if(!busy)setOpen(false);}} aria-labelledby="academy-closure-title"><header><div><small>학사일정 · 관리자 설정</small><h2 id="academy-closure-title">학원 휴강 관리</h2></div><button type="button" aria-label="닫기" disabled={busy} onClick={()=>setOpen(false)}>×</button></header><div className={styles.body}>
 <p className={styles.intro}>휴강일에는 선택한 수업을 쉬고, 실제 진행하는 수업만 따로 열 수 있습니다.</p>
 <div className={styles.list}>{rows.map(r=><button type="button" disabled={busy} key={r.id} className={editing?.id===r.id?styles.active:""} onClick={()=>edit(r)}><span><b>{r.reason}</b><small>{r.startsOn} ~ {r.endsOn}</small></span><em>{[r.regular&&"정규",r.correction&&"첨삭"].filter(Boolean).join(" · ")}</em></button>)}{!rows.length&&<p>등록된 휴강 일정이 없습니다.</p>}</div>
 <div className={styles.formHeading}><b>{editing?"휴강 일정 수정":"새 휴강 일정"}</b>{editing&&<button type="button" disabled={busy} onClick={reset}>새로 등록</button>}</div>
 <form id="academy-closure-form" onSubmit={e=>{e.preventDefault();void save();}}><div className={styles.dates}><label>시작일<input type="date" required disabled={busy} value={from} onChange={e=>{setFrom(e.target.value);if(to<e.target.value)setTo(e.target.value);}}/></label><label>종료일<input type="date" required min={from} disabled={busy} value={to} onChange={e=>setTo(e.target.value)}/></label></div><label>휴강 사유<input required maxLength={120} disabled={busy} value={reason} onChange={e=>setReason(e.target.value)} placeholder="예: 추석 연휴, 학원 내부 행사"/></label><fieldset disabled={busy}><legend>적용 대상</legend><label><input type="checkbox" checked={regular} onChange={e=>setRegular(e.target.checked)}/>정규수업</label><label><input type="checkbox" checked={correction} onChange={e=>setCorrection(e.target.checked)}/>첨삭</label></fieldset></form>
 <p className={styles.notice}>별도로 등록한 보강·추가수업은 유지됩니다. 휴강 안내 알림톡은 자동 발송되지 않습니다.</p>{error&&<p className={styles.error} role="alert">{error}</p>}</div><footer>{editing&&<button type="button" disabled={busy} onClick={()=>void save(true)}>휴강 취소</button>}<span/><button type="button" disabled={busy} onClick={()=>setOpen(false)}>닫기</button><button className={styles.primary} type="submit" form="academy-closure-form" disabled={busy||(!regular&&!correction)||!reason.trim()}>{busy?"저장 중…":editing?"변경 저장":"휴강 등록"}</button></footer></dialog></section>;
}

export function AcademyClosureNotice({supabase,date}:{supabase:SupabaseClient;date:string}){
 const[reasons,setReasons]=useState<string[]>([]);
 useEffect(()=>{let active=true;if(!date)return;void supabase.rpc("staff_academy_closures",{p_from:date,p_to:date}).then(({data,error})=>{if(active)setReasons(error?[]:(data as AcademyClosure[]??[]).map(r=>r.reason));});return()=>{active=false;};},[supabase,date]);
 return reasons.length?<p className={styles.notice}><b>학원 휴강일 · {reasons.join(" · ")}</b><br/>휴강일에 별도로 진행하는 보강·추가수업으로 등록됩니다.</p>:null;
}
