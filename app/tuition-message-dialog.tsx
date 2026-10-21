"use client";
import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import type { SupabaseClient } from "@supabase/supabase-js";
import styles from "./tuition-message.module.css";
export type TuitionMessageRow = {id:string;studentId:string;studentName:string;grade:string|null;school:string|null;status:string;totalAmount:number;paidAmount:number;balance:number};
type Preview = {history?:{chargeId:string;status:string;at:string}[];snapshot:TuitionMessageRow[];recipients:{phone:string;body:string;students:{chargeId:string;studentId:string;name:string}[]}[]};
const money=(n:number)=>`${n.toLocaleString("ko-KR")}원`;
const labels:Record<string,string>={paid:"납부 완료",open:"미납",partial:"부분 납부",waived:"면제"};
const templates={paid:"안녕하세요, 한살매입니다.\n{학생명} 학생의 {월} 수강료 {납부액}원 납부가 확인되었습니다. 감사합니다.",unpaid:"안녕하세요, 한살매입니다.\n{학생명} 학생의 {월} 수강료 잔여 금액은 {미납액}원입니다. 확인 부탁드립니다. 감사합니다.",general:"안녕하세요, 한살매입니다.\n{학생명} 학생의 {월} 수강료 안내입니다.\n청구액: {청구액}원\n납부액: {납부액}원\n잔여 금액: {미납액}원\n감사합니다."};
const defaultBody=(rows:TuitionMessageRow[])=>rows.length&&rows.every(r=>r.status==='paid')?templates.paid:rows.length&&rows.every(r=>r.status==='open'||r.status==='partial')?templates.unpaid:templates.general;
const matches=(row:TuitionMessageRow,grades:string[],statuses:string[])=>(!grades.length||grades.includes(row.grade||"학년 미등록"))&&(!statuses.length||statuses.includes(row.status));
export function TuitionMessageDialog({month,rows,initialGrades=[],initialStatuses=[],initialIds,supabase,onClose,onSaved}:{month:string;rows:TuitionMessageRow[];initialGrades?:string[];initialStatuses?:string[];initialIds?:string[];supabase:SupabaseClient;onClose:()=>void;onSaved:(count:number)=>void}){
 const dialog=useRef<HTMLDialogElement>(null),lock=useRef(false),requestId=useRef(crypto.randomUUID());
 const [grades,setGrades]=useState(initialGrades),[statuses,setStatuses]=useState(initialStatuses);
 const filtered=rows.filter(r=>matches(r,grades,statuses));
 const gradeOptions=[...new Set(rows.map(r=>r.grade||"학년 미등록"))].sort((a,b)=>a.localeCompare(b,"ko",{numeric:true}));
 const [selected,setSelected]=useState(()=>initialIds??rows.filter(r=>matches(r,initialGrades,initialStatuses)).map(r=>r.id));
 const targetIds=filtered.filter(r=>selected.includes(r.id)).map(r=>r.id);
 const [body,setBody]=useState(()=>defaultBody(rows.filter(r=>(initialIds?initialIds.includes(r.id):matches(r,initialGrades,initialStatuses)))));
 const [preview,setPreview]=useState<Preview|null>(null),[busy,setBusy]=useState(false),[error,setError]=useState('');
 useEffect(()=>{const d=dialog.current;d?.showModal();return()=>d?.close()},[]);
 const invalidate=()=>{setPreview(null);setError('');requestId.current=crypto.randomUUID()};
 function changeFilters(nextGrades:string[],nextStatuses:string[]){
  const next=rows.filter(r=>matches(r,nextGrades,nextStatuses));
  setGrades(nextGrades);setStatuses(nextStatuses);setSelected(next.map(r=>r.id));
  setBody(old=>Object.values(templates).includes(old)?defaultBody(next):old);invalidate();
 }
 async function prepare(){if(lock.current||!targetIds.length)return;lock.current=true;setBusy(true);setError('');try{const r=await supabase.rpc('staff_preview_tuition_messages',{p_month:month+'-01',p_charge_ids:targetIds,p_template:body});if(r.error)throw r.error;setPreview(r.data as Preview)}catch(e){setError((e as Error).message||'미리보기를 불러오지 못했습니다.')}finally{lock.current=false;setBusy(false)}}
 async function queue(){if(lock.current||!preview)return;lock.current=true;setBusy(true);setError('');try{const r=await supabase.rpc('staff_queue_tuition_messages',{p_month:month+'-01',p_charge_ids:targetIds,p_template:body,p_expected:preview,p_request_id:requestId.current});if(r.error)throw r.error;onSaved(Number(r.data??0))}catch(e){setError((e as Error).message||'등록 결과를 확인하지 못했습니다. 다시 시도해 주세요.')}finally{lock.current=false;setBusy(false)}}
 const included=new Set(preview?.recipients.flatMap(r=>r.students.map(s=>s.chargeId))??[]);
 return createPortal(<dialog ref={dialog} className={styles.dialog} aria-labelledby="tuition-message-title" onCancel={e=>{e.preventDefault();if(!busy)onClose()}}>
 <header><div><small>TUITION MESSAGE</small><h2 id="tuition-message-title">원비 문자 작성</h2><p>{month.replace('-','년 ')}월 · 분류 대상 {rows.length}명 · 학부모 수신</p></div><button type="button" disabled={busy} onClick={onClose} aria-label="원비 문자 닫기">×</button></header>
 <div className={styles.content}>
 <section className={styles.filters} aria-label="문자 대상 분류"><div className={styles.actions}><b>학년·납부 상태로 분류</b><button disabled={busy} onClick={()=>changeFilters([],[])}>분류 초기화</button></div><p>조회 월 전체 명단에서 여러 조건을 함께 선택할 수 있어요. 조건을 바꾸면 해당 학생들이 선택됩니다.</p>
 <div className={styles.filterRow} role="group" aria-label="문자 대상 학년"><strong>학년</strong><button disabled={busy} aria-pressed={!grades.length} onClick={()=>changeFilters([],statuses)}>전체 학년</button>{gradeOptions.map(g=><button key={g} disabled={busy} aria-pressed={grades.includes(g)} onClick={()=>changeFilters(grades.includes(g)?grades.filter(x=>x!==g):[...grades,g],statuses)}>{g}</button>)}</div>
 <div className={styles.filterRow} role="group" aria-label="문자 대상 납부 상태"><strong>납부 상태</strong><button disabled={busy} aria-pressed={!statuses.length} onClick={()=>changeFilters(grades,[])}>전체 상태</button>{["open","partial","paid","waived"].map(status=><button key={status} disabled={busy} aria-pressed={statuses.includes(status)} onClick={()=>changeFilters(grades,statuses.includes(status)?statuses.filter(x=>x!==status):[...statuses,status])}>{labels[status]}</button>)}</div></section>
 <section><div className={styles.actions}><b>선택 학생 {targetIds.length}명 / 분류 결과 {filtered.length}명</b><button disabled={busy} onClick={()=>{setSelected(filtered.map(r=>r.id));invalidate()}}>전체 선택</button><button disabled={busy} onClick={()=>{setSelected([]);invalidate()}}>전체 해제</button></div><div className={styles.students}>{filtered.map(r=><label key={r.id}><input type="checkbox" disabled={busy} checked={selected.includes(r.id)} onChange={()=>{setSelected(old=>old.includes(r.id)?old.filter(id=>id!==r.id):[...old,r.id]);invalidate()}}/><span><b>{r.studentName}</b><small>{r.school} {r.grade} · {labels[r.status]}</small></span><span>납부 {money(r.paidAmount)}<small>잔여 {money(r.balance)}</small></span></label>)}{!filtered.length&&<p className={styles.empty}>조건에 맞는 학생이 없습니다. 학년이나 납부 상태를 변경해 주세요.</p>}</div></section>
 <section><div className={styles.actions}><b>문자 내용</b><select aria-label="원비 문자 기본 문구" disabled={busy} defaultValue="" onChange={e=>{if(e.target.value){setBody(templates[e.target.value as keyof typeof templates]);invalidate()}}}><option value="" disabled>기본 문구 선택</option><option value="paid">납부 확인</option><option value="unpaid">미납 안내</option><option value="general">납부 내역 안내</option></select></div><textarea aria-label="원비 문자 내용" disabled={busy} maxLength={1500} value={body} onChange={e=>{setBody(e.target.value);invalidate()}}/><p className={styles.help}>자동 입력: {'{학생명} · {월} · {청구액} · {납부액} · {미납액} · {납부상태}'}<br/>문구는 자유롭게 수정할 수 있습니다. 같은 번호의 형제자매 안내는 한 문자로 합칩니다.</p></section>
 {preview&&<section className={styles.preview}><h3>발송 전 확인 · {preview.recipients.length}개 번호</h3><p>최신 납부 정보를 반영한 내용입니다. 금액과 수신자를 확인해 주세요.</p>{preview.history?.map(h=><p key={h.chargeId}>{preview.snapshot.find(r=>r.id===h.chargeId)?.studentName} · 최근 원비 문자: {new Date(h.at).toLocaleString("ko-KR",{timeZone:"Asia/Seoul"})} · {({sent:"발송 완료",pending_approval:"발송 대기",failed:"실패",sending:"발송 중",cancelled:"취소"} as Record<string,string>)[h.status]??h.status}</p>)}{preview.snapshot.filter(r=>!included.has(r.id)).map(r=><p className={styles.warning} key={r.id}>{r.studentName}: 유효한 학부모 휴대폰 번호가 없어 제외됩니다.</p>)}{preview.recipients.map(r=><article key={r.phone}><b>{r.students.map(s=>s.name).join(' · ')} 학부모</b><small>{r.phone}</small><pre>{r.body}</pre></article>)}</section>}
 {error&&<p role="alert" className={styles.warning}>{error}</p>}
 <p className={styles.help}>등록한 문자는 기존 ‘문자 발송’ 대기열에서 확인 후 발송합니다. 실제 발송 직전에도 납부 상태·금액·연락처 변경 여부를 확인합니다.</p></div>
 <footer><button disabled={busy} onClick={onClose}>닫기</button><button disabled={busy||!targetIds.length||!body.trim()} onClick={()=>void prepare()}>최신 정보로 미리보기</button><button className={styles.primary} disabled={busy||!preview?.recipients.length} onClick={()=>void queue()}>{busy?'확인 중…':`문자 대기열 등록${preview?` · ${preview.recipients.length}건`:''}`}</button></footer>
 </dialog>,document.body);
}
