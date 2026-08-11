"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type AuditView="settings"|"students"|"schedule"|"attendance"|"assignments";
type AuditItem={ id:string; name:string; detail:string };
type AuditCategory={ key:string; title:string; description:string; severity:"critical"|"warning"|"info"; actionLabel:string; actionView:AuditView; count:number; items:AuditItem[] };
type AuditData={ checkedAt:string; categories:AuditCategory[] };

export function OperationsAuditBoard({supabase,onNavigate}:{supabase:SupabaseClient;onNavigate:(view:AuditView)=>void}){
  const [data,setData]=useState<AuditData|null>(null); const [loading,setLoading]=useState(true); const [error,setError]=useState(""); const [filter,setFilter]=useState<"problems"|"all"|"complete">("problems");
  const load=useCallback(async()=>{setLoading(true);setError("");const{data:next,error:loadError}=await supabase.rpc("admin_operations_audit");if(loadError)setError("운영 점검 결과를 불러오지 못했습니다. 관리자 계정인지 확인해 주세요.");else setData(next as AuditData);setLoading(false);},[supabase]);
  useEffect(()=>{void load();},[load]);
  const categories=useMemo(()=>data?.categories.filter((item)=>filter==="all"||(filter==="problems"?item.count>0:item.count===0))??[],[data,filter]);
  const issueCount=data?.categories.reduce((sum,item)=>sum+item.count,0)??0; const completeCount=data?.categories.filter((item)=>item.count===0).length??0;
  if(loading&&!data)return <section className="panel settings-empty">학원 운영 상태를 점검하는 중이에요…</section>;
  return <><div className="page-heading compact audit-heading"><div><p className="eyebrow">관리자 전용</p><h1>운영 점검</h1><p>계정·학생·클래스 설정에서 빠진 항목을 자동으로 확인합니다.</p></div><button className="secondary-button" disabled={loading} onClick={()=>void load()}>{loading?"점검 중…":"↻ 다시 점검"}</button></div>{error&&<p className="attendance-error">{error}</p>}<section className="audit-summary"><article className={issueCount?"warning":"healthy"}><i>{issueCount?"!":"✓"}</i><span><b>{issueCount?`${issueCount}건을 확인해 주세요`:`모든 점검을 통과했어요`}</b><small>{data?`${formatDateTime(data.checkedAt)} 기준`:""}</small></span></article><div><span>전체 점검 <b>{data?.categories.length??0}</b></span><span>정상 <b>{completeCount}</b></span><span>확인 필요 <b>{data?.categories.filter((item)=>item.count>0).length??0}</b></span></div></section><div className="audit-filters"><button className={filter==="problems"?"active":""} onClick={()=>setFilter("problems")}>확인 필요</button><button className={filter==="complete"?"active":""} onClick={()=>setFilter("complete")}>정상</button><button className={filter==="all"?"active":""} onClick={()=>setFilter("all")}>전체</button></div><section className="audit-grid">{categories.map((category)=><article className={`panel audit-card ${category.count?category.severity:"complete"}`} key={category.key}><header><i>{category.count?category.severity==="critical"?"!":"△":"✓"}</i><span><h2>{category.title}</h2><p>{category.description}</p></span><strong>{category.count?`${category.count}건`:"정상"}</strong></header>{category.count>0&&<div className="audit-items">{category.items.map((item)=><p key={`${category.key}-${item.id}`}><span><b>{item.name}</b><small>{item.detail}</small></span></p>)}{category.count>category.items.length&&<em>외 {category.count-category.items.length}건</em>}</div>}<footer><button onClick={()=>onNavigate(category.actionView)}>{category.actionLabel}로 이동 ›</button></footer></article>)}{categories.length===0&&<p className="panel settings-empty">이 조건에 해당하는 점검 항목이 없습니다.</p>}</section></>;
}
function formatDateTime(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",year:"numeric",month:"long",day:"numeric",hour:"2-digit",minute:"2-digit",hour12:false}).format(new Date(value))}
