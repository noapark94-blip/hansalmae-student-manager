"use client";

import { useCallback, useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { HansalmaeIcon } from "./hansalmae-icons";

export type StudentStatusFilter="all"|"active"|"paused"|"completed";
type RecentChange={id:string;studentId:string;studentName:string;previousStatus:string;newStatus:string;effectiveOn:string;note:string|null;changedByName:string};
type DashboardData={current:{all:number;active:number;paused:number;completed:number};period:{active:number;paused:number;completed:number};recent:RecentChange[]};
const labels:Record<Exclude<StudentStatusFilter,"all">,string>={active:"재원",paused:"휴원",completed:"퇴원"};

export function StudentLifecycleDashboard({supabase,filter,onFilter}:{supabase:SupabaseClient;filter:StudentStatusFilter;onFilter:(filter:StudentStatusFilter)=>void}){
  const [days,setDays]=useState(30); const [data,setData]=useState<DashboardData|null>(null); const [loading,setLoading]=useState(true); const [error,setError]=useState("");
  const load=useCallback(async()=>{setLoading(true);setError("");const{data:next,error:loadError}=await supabase.rpc("staff_student_lifecycle_dashboard",{p_days:days});if(loadError){setError("재원 변동 현황을 불러오지 못했습니다.");setData(null);}else setData(next as DashboardData);setLoading(false);},[days,supabase]);
  useEffect(()=>{void load();},[load]);
  const cards:[StudentStatusFilter,string,"students"|"check"|"pause"|"circle"][]=[["all","전체 학생","students"],["active","재원","check"],["paused","휴원","pause"],["completed","퇴원","circle"]];
  return <section className="lifecycle-dashboard"><header><div><p className="eyebrow">재원 변동 현황</p><h2>학생 상태를 한눈에 확인하세요</h2></div><select aria-label="조회 기간" value={days} onChange={(event)=>setDays(Number(event.target.value))}><option value={30}>최근 30일</option><option value={90}>최근 90일</option></select></header>{error&&<p className="lifecycle-dashboard-error">{error}</p>}<div className="lifecycle-status-cards">{cards.map(([id,label,icon])=><button key={id} className={filter===id?"active":""} onClick={()=>onFilter(id)}><i>{id==="all"?<HansalmaeIcon name="students" size={22}/>:icon==="check"?"✓":icon==="pause"?"Ⅱ":"○"}</i><span><small>{label}</small><b>{loading?"…":data?.current[id]??0}<em>명</em></b>{id!=="all"&&<strong>기간 내 {data?.period[id]??0}명 변동</strong>}</span></button>)}</div><div className="lifecycle-recent"><header><h3>최근 처리 내역</h3><span>{days}일 기준</span></header>{loading?<p>변동 내역을 불러오는 중이에요…</p>:data?.recent.length?data.recent.map((item)=><article key={item.id}><time>{formatDate(item.effectiveOn)}</time><span><b>{item.studentName}</b><small>{statusLabel(item.previousStatus)} → {statusLabel(item.newStatus)} · {item.changedByName}</small>{item.note&&<p>{item.note}</p>}</span><i className={normalize(item.newStatus)}>{statusLabel(item.newStatus)}</i></article>):<p>해당 기간의 변동 내역이 없습니다.</p>}</div></section>;
}
function normalize(value:string){return value==="active"||value==="재원"?"active":value==="paused"||value==="휴원"?"paused":"completed"}
function statusLabel(value:string){return labels[normalize(value)]}
function formatDate(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"short",day:"numeric"}).format(new Date(value))}
