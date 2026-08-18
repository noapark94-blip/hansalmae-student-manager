"use client";

import { useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type Exam={id:string;lessonDate:string;className:string;subject:string;examTitle:string|null;score:number|null;maxScore:number;percent:number|null};

export function FamilyExamGrowth({supabase,studentId}:{supabase:SupabaseClient;studentId:string}){
  const[regular,setRegular]=useState<Exam[]>([]);const[correction,setCorrection]=useState<Exam[]>([]);const[loading,setLoading]=useState(true);
  useEffect(()=>{let active=true;setLoading(true);void Promise.all([supabase.rpc("family_exam_progress",{p_student_id:studentId}),supabase.rpc("family_correction_exam_progress",{p_student_id:studentId})]).then(([a,b])=>{if(active){setRegular((a.data??[]) as Exam[]);setCorrection((b.data??[]) as Exam[]);setLoading(false);}});return()=>{active=false};},[studentId,supabase]);
  if(loading)return null;
  return <div className="family-growth-split"><ExamGrowthCard title="정규수업 시험 성적 추이" eyebrow="정규수업 성적 성장" items={regular}/><ExamGrowthCard title="첨삭수업 시험 성적 추이" eyebrow="첨삭수업 성적 성장" items={correction}/></div>;
}

function ExamGrowthCard({title,eyebrow,items}:{title:string;eyebrow:string;items:Exam[]}){
  const[subject,setSubject]=useState("");
  const subjects=useMemo(()=>Array.from(new Set(items.map(x=>x.subject).filter(Boolean))),[items]);
  const selected=subject&&subjects.includes(subject)?subject:(subjects[0]??"");
  const rows=useMemo(()=>items.filter(x=>x.subject===selected&&x.percent!==null).slice(0,8).reverse(),[items,selected]);
  const recent=rows.slice(-3);const average=recent.length?Math.round(recent.reduce((sum,x)=>sum+(x.percent??0),0)/recent.length*10)/10:null;
  const delta=rows.length>=2?Math.round(((rows.at(-1)?.percent??0)-(rows.at(-2)?.percent??0))*10)/10:null;
  return <section className="panel family-growth-card">
    <header><div><p className="eyebrow">{eyebrow}</p><h2>{title}</h2></div>{subjects.length>0&&<nav>{subjects.map(name=><button key={name} className={selected===name?"active":""} onClick={()=>setSubject(name)}>{name}</button>)}</nav>}</header>
    {!subjects.length?<p className="family-list-empty">아직 점수가 입력된 시험이 없습니다.</p>:<><div className="family-growth-summary"><span><small>최근 3회 평균</small><b>{average===null?"–":`${average}점`}</b></span><span><small>직전 시험 대비</small><b className={delta===null?"":delta>0?"up":delta<0?"down":""}>{delta===null?"–":delta>0?`+${delta}점`:delta===0?"변동 없음":`${delta}점`}</b></span><span><small>기록된 시험</small><b>{rows.length}회</b></span></div>{rows.length?<div className="family-growth-chart" aria-label={`${selected} ${title}`}>{rows.map((item,index)=><div key={item.id} className="family-growth-bar"><span><i style={{height:`${Math.max(6,Math.min(100,item.percent??0))}%`}}/><em>{formatPercent(item.percent)}</em></span><small>{shortDate(item.lessonDate)}</small><b title={item.examTitle??item.className}>{item.examTitle||item.className}</b>{index===rows.length-1&&<strong>최근</strong>}</div>)}</div>:<p className="family-list-empty">점수가 입력된 시험이 아직 없습니다.</p>}</>}
  </section>;
}
function shortDate(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"numeric",day:"numeric"}).format(new Date(`${value}T12:00:00+09:00`));}
function formatPercent(value:number|null){return value===null?"–":`${Number(value).toFixed(Number(value)%1?1:0)}점`;}
