"use client";
import {useEffect,useState} from "react";
import type {SupabaseClient} from "@supabase/supabase-js";
import styles from "./special-student-kind.module.css";
export type StudentLessonKind={kind:"makeup"|"additional";source?:string|null;sourceId?:string|null};
type Absence={source:string;sourceId:string;date:string;title:string;subjectId:string|null};
export function SpecialStudentKind({supabase,studentId,name,sessionId,value,onChange,disabled}:{supabase:SupabaseClient;studentId:string;name:string;sessionId:string;value:StudentLessonKind;onChange:(value:StudentLessonKind)=>void;disabled:boolean}){
 const requestKey=`${studentId}:${sessionId}`;
 const [result,setResult]=useState<{key:string;options:Absence[];error:string}|null>(null);
 const loading=value.kind==='makeup'&&result?.key!==requestKey;
 const options=result?.key===requestKey?result.options:[];
 const error=result?.key===requestKey?result.error:'';
 useEffect(()=>{
  let active=true;
  if(value.kind!=='makeup')return;
  Promise.resolve(supabase.rpc('staff_special_absence_options',{p_student_id:studentId,p_session_id:sessionId||null}))
   .then(({data,error})=>{if(active)setResult({key:requestKey,options:data??[],error:error?'결석 기록을 불러오지 못했습니다.':''});})
   .catch(()=>{if(active)setResult({key:requestKey,options:[],error:'결석 기록을 불러오지 못했습니다.'});});
  return()=>{active=false;};
 },[supabase,studentId,sessionId,value.kind,requestKey]);
 return <div className={styles.row}><div className={styles.heading}><b>{name}</b><div className={styles.segment} role="group" aria-label={`${name} 수업 구분`}>{([['additional','추가수업'],['makeup','보강']] as const).map(([kind,label])=><button type="button" key={kind} aria-pressed={value.kind===kind} disabled={disabled} onClick={()=>onChange({kind})}>{label}</button>)}</div></div>{value.kind==="makeup"&&<label className={styles.link}>결석 수업 연결 <span>선택</span><select aria-label={`${name} 결석 수업 연결`} disabled={disabled||loading||Boolean(error)} value={value.sourceId?`${value.source}:${value.sourceId}`:""} onChange={e=>{const option=options.find(o=>`${o.source}:${o.sourceId}`===e.target.value);onChange({kind:'makeup',source:option?.source,sourceId:option?.sourceId});}}><option value="">{loading?"결석 기록을 불러오는 중…":error||"연결 없이 보강으로 등록"}</option>{options.map(o=><option key={`${o.source}:${o.sourceId}`} value={`${o.source}:${o.sourceId}`}>{o.date} · {o.title}</option>)}</select>{error&&<small role="alert">{error} 창을 다시 열어 주세요.</small>}</label>}</div>;
}
