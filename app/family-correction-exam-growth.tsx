"use client";
import { useEffect,useMemo,useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
type Exam={id:string;correctionDate:string;subject:string;examTitle:string|null;examScore:number|null;examMaxScore:number|null};
export function FamilyCorrectionExamGrowth({supabase,studentId}:{supabase:SupabaseClient;studentId:string}){
 const[items,setItems]=useState<Exam[]>([]);const[subject,setSubject]=useState("");const[loading,setLoading]=useState(true);
 useEffect(()=>{let active=true;setLoading(true);void supabase.rpc("family_correction_reports",{p_student_id:studentId,p_limit:50}).then(({data})=>{if(active){setItems(((data??[]) as Exam[]).filter(x=>x.examScore!==null&&x.examMaxScore));setLoading(false)}});return()=>{active=false}},[studentId,supabase]);
 const subjects=useMemo(()=>Array.from(new Set(items.map(x=>x.subject).filter(Boolean))),[items]);const selected=subject&&subjects.includes(subject)?subject:(subjects[0]??"");
 const rows=useMemo(()=>items.filter(x=>x.subject===selected).slice(0,8).reverse().map(x=>({...x,percent:x.examMaxScore?Math.round((Number(x.examScore)/Number(x.examMaxScore))*1000)/10:0})),[items,selected]);
 const recent=rows.slice(-3),average=recent.length?Math.round(recent.reduce((s,x)=>s+x.percent,0)/recent.length*10)/10:null,delta=rows.length>=2?Math.round((rows.at(-1)!.percent-rows.at(-2)!.percent)*10)/10:null;
 if(loading||!subjects.length)return null;
 return <section className="panel family-growth-card family-correction-growth"><header><div><p className="eyebrow">첨삭 성적 성장</p><h2>첨삭수업 시험 성적 추이</h2></div><nav>{subjects.map(name=><button key={name} className={selected===name?"active":""} onClick={()=>setSubject(name)}>{name}</button>)}</nav></header><div className="family-growth-summary"><span><small>최근 3회 평균</small><b>{average===null?"–":`${average}점`}</b></span><span><small>직전 시험 대비</small><b className={delta===null?"":delta>0?"up":delta<0?"down":""}>{delta===null?"–":delta>0?`+${delta}점`:delta===0?"변동 없음":`${delta}점`}</b></span><span><small>첨삭 시험</small><b>{rows.length}회</b></span></div><div className="family-growth-chart" aria-label={`${selected} 첨삭 시험 점수 추이`}>{rows.map((x,index)=><div key={x.id} className="family-growth-bar"><span><i style={{height:`${Math.max(6,Math.min(100,x.percent))}%`}}/><em>{Number(x.percent).toFixed(x.percent%1?1:0)}점</em></span><small>{shortDate(x.correctionDate)}</small><b title={x.examTitle??"첨삭 시험"}>{x.examTitle||"첨삭 시험"}</b>{index===rows.length-1&&<strong>최근</strong>}</div>)}</div></section>;
}
function shortDate(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"numeric",day:"numeric"}).format(new Date(`${value}T12:00:00+09:00`))}
