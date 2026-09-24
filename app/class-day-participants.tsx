"use client";

import { useEffect, useRef, useState } from "react";
import styles from "./class-day-participants.module.css";

export type Participant = {id:string;name:string;school:string|null;grade:string|null;excluded?:boolean;exclusionReason?:string;recordExists?:boolean};
export type ParticipationChange = {studentId:string;excluded:boolean;reason:string};

export function ClassDayParticipants({date,students,disabled,version,onApply}:{date:string;students:Participant[];disabled:boolean;version:string;onApply:(changes:ParticipationChange[],version:string)=>Promise<void>}) {
 const [open,setOpen]=useState(false);
 const [selected,setSelected]=useState<Set<string>>(new Set());
 const [reason,setReason]=useState("");
 const [busy,setBusy]=useState(false);
 const [error,setError]=useState("");
 const [confirmAll,setConfirmAll]=useState(false);
 const dialog=useRef<HTMLDialogElement>(null);
 const [baseline,setBaseline]=useState<Participant[]>([]);
 const openedVersion=useRef("");
 const trigger=useRef<HTMLButtonElement>(null);
 const excluded=students.filter(s=>s.excluded);
 const dateLabel=`${Number(date.slice(5,7))}월 ${Number(date.slice(8,10))}일`;
 useEffect(()=>{if(open)dialog.current?.showModal();else dialog.current?.close();},[open]);
 function close(){if(busy)return;setOpen(false);trigger.current?.focus();}
 function launch(){openedVersion.current=version;setBaseline(students.map(s=>({...s})));setSelected(new Set(students.filter(s=>!s.excluded).map(s=>s.id)));setReason("");setError("");setConfirmAll(false);setOpen(true);}
 const changes=baseline.filter(s=>Boolean(s.excluded)===selected.has(s.id)).map(s=>({studentId:s.id,excluded:!selected.has(s.id),reason:!selected.has(s.id)?reason.trim():s.exclusionReason??""}));
 const newlyExcluded=baseline.filter(s=>!s.excluded&&!selected.has(s.id));
 const recorded=newlyExcluded.filter(s=>s.recordExists);
 async function apply(){
  if(!changes.length||busy||(!selected.size&&!confirmAll))return;
  setBusy(true);setError("");
  try{await onApply(changes,openedVersion.current);setOpen(false);trigger.current?.focus();}catch(e){setError(e instanceof Error?e.message:"수업 대상을 변경하지 못했습니다.");}finally{setBusy(false);}
 }
 return <section className={styles.panel} aria-label="날짜별 수업 대상">
  <div className={styles.bar}><div><span className={styles.eyebrow}>{dateLabel} 수업 대상</span><strong>{students.length-excluded.length}명 <small>/ 전체 {students.length}명</small></strong></div><button ref={trigger} type="button" disabled={disabled||!students.length} onClick={launch}>오늘 수업 대상 변경</button></div>
  {excluded.length>0&&<details className={styles.excluded}><summary>오늘 제외된 학생 <b>{excluded.length}명</b></summary><ul>{excluded.map(s=><li key={s.id}><b>{s.name}</b><span>{s.exclusionReason||"사유 미입력"}</span></li>)}</ul><p>선택한 날짜에만 적용됩니다. 다시 포함하려면 수업 대상을 변경해 주세요.</p></details>}
  <dialog ref={dialog} className={styles.dialog} onCancel={event=>{event.preventDefault();close();}} onClick={event=>{if(event.target===event.currentTarget)close();}} aria-labelledby="participants-title">
   {open&&<><header><div><span className={styles.eyebrow}>{dateLabel}에만 적용</span><h3 id="participants-title">오늘 수업 대상 변경</h3></div><button type="button" disabled={busy} onClick={close} aria-label="닫기">×</button></header>
   <div className={styles.body}><p className={styles.description}>수업을 받기로 한 학생을 선택해 주세요.<br/>체크를 해제한 학생은 오늘 수업에서 제외됩니다.</p>
    <div className={styles.selection}><strong>수업 대상 {selected.size}명 <span>· 제외 {baseline.length-selected.size}명</span></strong><button type="button" disabled={busy} onClick={()=>{setSelected(new Set(baseline.map(s=>s.id)));setConfirmAll(false);}}>전체 선택</button></div>
    <div className={styles.students}>{baseline.map(s=><label key={s.id} className={!selected.has(s.id)?styles.unchecked:undefined}><input type="checkbox" disabled={busy} checked={selected.has(s.id)} onChange={e=>{const next=new Set(selected);if(e.target.checked)next.add(s.id);else next.delete(s.id);setSelected(next);setConfirmAll(false);}}/><span><b>{s.name}</b><small>{[s.school,s.grade].filter(Boolean).join(" · ")}</small></span><em>{selected.has(s.id)?"수업 대상":"제외"}</em></label>)}</div>
    <label className={styles.reason}><span>제외 사유 <small>선택 · 선생님과 관리자만 확인</small></span><input maxLength={120} value={reason} disabled={busy||!newlyExcluded.length} onChange={e=>setReason(e.target.value)} placeholder="예: 추석 연휴, 학교 행사"/><small>이번에 제외하는 학생에게 같은 사유를 적용합니다.</small></label>
    <div className={styles.notice}>제외된 수업은 학부모 기록·알림톡·출결 집계에 반영되지 않습니다. 작성한 기록은 보관되며, 다시 포함하면 복구됩니다. 이미 보낸 알림톡은 변경되지 않습니다.</div>
    {recorded.length>0&&<p className={styles.warning}><b>{recorded.map(s=>s.name).join(", ")}</b> 학생은 작성한 기록이 있습니다. 제외하면 기존에 공개된 해당 수업 기록도 숨겨집니다.</p>}
    {!selected.size&&<label className={styles.warning}><input type="checkbox" disabled={busy} checked={confirmAll} onChange={e=>setConfirmAll(e.target.checked)}/> 오늘 전체 학생을 제외하는 것을 확인했습니다.</label>}
    {error&&<p className={styles.error} role="alert">{error}</p>}
   </div><footer><button type="button" disabled={busy} onClick={close}>취소</button><button type="button" className={styles.primary} disabled={busy||!changes.length||(!selected.size&&!confirmAll)} onClick={()=>void apply()}>{busy?"적용 중…":"오늘만 적용"}</button></footer></>}
  </dialog>
 </section>;
}
