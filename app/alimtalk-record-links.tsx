"use client";
import {useEffect,useRef,useState} from 'react';
import type {SupabaseClient} from '@supabase/supabase-js';
import {useRecordWorkOpen} from './record-work';
import type {RecordWorkItem} from './record-work-model';
import styles from './alimtalk-record-links.module.css';
export type Section='lesson'|'exam'|'homework'|'correction';
export type LinkRef={lessonId:string;source:string;subject:string;lessonDate:string;className:string;exam:boolean;homework:boolean;correction:boolean;target:Pick<RecordWorkItem,'source'|'classId'|'sessionId'|'assignmentId'|'date'|'time'|'title'|'kind'>|null};
type Links={mode:'saved'|'history'|'current';studentId:string;items:LinkRef[]};
export function messageParts(body:string){
 let section:Section='lesson';
 return body.split('\n').map(text=>{if(text.startsWith('■'))section='lesson';if(text==='<시험>')section='exam';if(text==='<숙제>')section='homework';if(text==='<첨삭 과제>')section='correction';return {text,section,linked:text.startsWith('- ')};});
}
export function candidates(items:LinkRef[],section:Section,line:string){
 return items.filter(r=>{
  if(section!=='lesson'&&!r[section])return false;
  const prefix=`- ${r.subject}`;
  if(!line.startsWith(prefix+':')&&!line.startsWith(prefix+' '))return false;
  if(section==='lesson'){
   const suffix=line.slice(prefix.length);
   if(suffix.startsWith(' 수업'))return r.source==='regular';
   if(suffix.startsWith(' 보강'))return r.source==='makeup';
   if(suffix.startsWith(' 추가수업'))return r.source==='extra';
   if(suffix.startsWith(' 첨삭'))return r.source==='correction';
  }
  return true;
 });
}
export function LinkedAlimtalkBody({body,supabase,studentId,studentName,from,to,deliveryId}:{body:string;supabase:SupabaseClient;studentId:string;studentName:string;from:string;to:string;deliveryId?:string}){
 const open=useRecordWorkOpen();
 const [selection,setSelection]=useState<{links:Links;rows:LinkRef[];section:Section}|null>(null),[loading,setLoading]=useState(false),[error,setError]=useState('');
 const generation=useRef(0);
 useEffect(()=>()=>{generation.current++},[]);
 const jump=(r:LinkRef,section:Section)=>{if(!r.target||!open)return;open({...r.target,key:`alimtalk:${r.source}:${r.lessonId}:${studentId}`,studentId,studentName,endTime:null,due:false,owners:[],reason:'',requestedAt:null,origin:'alimtalk',focusSection:section});};
 const resolve=async(section:Section,line:string)=>{const id=++generation.current;setLoading(true);setError('');setSelection(null);try{
  const result=await supabase.rpc('staff_alimtalk_record_links',{p_delivery_id:deliveryId??null,p_student_id:deliveryId?null:studentId,p_from:deliveryId?null:from,p_to:deliveryId?null:to});
  if(id!==generation.current)return;if(result.error)throw result.error;
  const links=result.data as Links;const rows=candidates(links.items,section,line);
  if(links.mode!=='history'&&rows.length===1&&rows[0].target){jump(rows[0],section);return;}
  setSelection({links,rows,section});
 }catch{if(id===generation.current)setError('원본 기록을 불러오지 못했습니다. 항목을 다시 눌러 주세요.');}finally{if(id===generation.current)setLoading(false);}};
 return <><p className={styles.hint}>밑줄이 있는 항목을 누르면 수업 기록을 확인할 수 있습니다.</p><pre className={styles.body}>{messageParts(body).map((p,i)=><span key={i}>{i>0?'\n':''}{p.linked&&open?<button type="button" className={`${styles.line} ${styles.link}`} aria-label={`${p.text.slice(2)} 원본 기록 보기`} onClick={()=>void resolve(p.section,p.text)}>{p.text}</button>:p.text}</span>)}</pre>
 {loading&&<p className={styles.hint} role="status">연결된 기록을 확인하고 있어요.</p>}{error&&<p className={styles.notice} role="alert">{error}</p>}
 {selection&&<section className={styles.sources} aria-label="연결된 수업 기록"><header><b>수업 기록 선택</b><button type="button" onClick={()=>setSelection(null)} aria-label="기록 선택 닫기">×</button></header><p>{selection.links.mode==='history'?'이전 발송 건은 원본 번호가 저장되지 않아 해당 기간의 현재 기록을 표시합니다. 날짜와 수업을 확인해 선택해 주세요.':'여러 수업이 포함된 항목입니다. 확인할 수업을 선택해 주세요.'}</p>{selection.rows.length?selection.rows.map(r=><button type="button" className={styles.source} key={r.source+':'+r.lessonId} disabled={!r.target} onClick={()=>jump(r,selection.section)}><span><b>{r.subject} · {r.className}</b><small>{r.target?.date??r.lessonDate} · {r.target?.time??'시간 미정'} · {r.target?.kind??'원본 삭제 또는 연결 불가'}</small></span><span aria-hidden="true">→</span></button>):<p>정확히 연결할 기록을 찾지 못했습니다. 원본이 수정되거나 삭제되었을 수 있습니다.</p>}<small>원본 화면은 현재 저장된 기록입니다. 발송 당시 내용과 다를 수 있습니다.</small></section>}
 </>;
}
