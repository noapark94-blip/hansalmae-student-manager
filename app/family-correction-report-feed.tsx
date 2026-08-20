"use client";

import { useEffect,useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { HansalmaeIcon } from "./hansalmae-icons";

type Report={id:string;correctionDate:string;startTime:string;endTime:string;subject:string;attendanceStatus:string;lateMinutes:number|null;examTitle:string;examRange:string;examScore:number|null;examMaxScore:number|null;evaluation:string;homeworkInstruction:string;homeworkStatus:string|null;homeworkNote:string;correctionContent:string;assistantFeedback:string;nextPreparation:string;recordedByName:string|null};
type Read={reportId:string;viewedAt:string};
const attendance:Record<string,string>={scheduled:"미기록",present:"출석",late:"지각",absent:"결석"};

export function FamilyCorrectionReportFeed({supabase,studentId}:{supabase:SupabaseClient;studentId:string}){
 const[items,setItems]=useState<Report[]>([]);const[reads,setReads]=useState<Record<string,string>>({});const[loading,setLoading]=useState(true);const[unavailable,setUnavailable]=useState(false);const[confirming,setConfirming]=useState<string|null>(null);
 useEffect(()=>{let active=true;setLoading(true);setUnavailable(false);void(async()=>{const reports=await supabase.rpc("family_correction_reports",{p_student_id:studentId,p_limit:20});if(!active)return;if(reports.error){setUnavailable(true);setLoading(false);return}setItems((reports.data??[]) as Report[]);const readResult=await supabase.rpc("family_correction_report_reads",{p_student_id:studentId});if(!active)return;if(!readResult.error){const next:Record<string,string>={};for(const row of (readResult.data??[]) as Read[])next[row.reportId]=row.viewedAt;setReads(next)}setLoading(false)})();return()=>{active=false}},[studentId,supabase]);
 async function confirm(id:string){if(reads[id]||confirming)return;setConfirming(id);const{data,error}=await supabase.rpc("mark_family_correction_report_read",{p_student_id:studentId,p_report_id:id});if(!error)setReads(current=>({...current,[id]:String(data??new Date().toISOString())}));setConfirming(null)}
 if(unavailable)return null;
 const unread=items.filter(item=>!reads[item.id]).length;
 return <section className="family-correction-feed"><header><div><p className="eyebrow">주간 첨삭 기록</p><h2>첨삭 리포트</h2><span>첨삭 시간에 진행한 과제와 시험 결과를 확인하세요.</span></div>{unread>0&&<strong>새 리포트 {unread}</strong>}</header>{loading?<p className="family-correction-empty">첨삭 리포트를 불러오는 중이에요…</p>:!items.length?<p className="family-correction-empty">아직 등록된 첨삭 리포트가 없습니다.</p>:<div className="family-correction-list">{items.map(item=><article key={item.id} className={!reads[item.id]?"unread":""}><header><span><em>{item.subject} 첨삭</em><h3>{formatDate(item.correctionDate)}</h3><small>{item.startTime.slice(0,5)}–{item.endTime.slice(0,5)}{item.recordedByName?` · ${item.recordedByName} 선생님`:""}</small></span><b>{attendance[item.attendanceStatus]??item.attendanceStatus}{item.attendanceStatus==="late"&&item.lateMinutes?` ${item.lateMinutes}분`:""}</b></header><div className="family-correction-body">{item.examTitle&&<Info icon="chart" title={item.examTitle} text={[cleanRange(item.examRange),item.examScore==null?null:`${score(item.examScore)} / ${score(item.examMaxScore??100)}점`,item.evaluation].filter(Boolean).join(" · ")}/>} {item.correctionContent&&<Info icon="book" title="오늘 한 첨삭과제" text={item.correctionContent}/>} {item.assistantFeedback&&<section className="family-correction-feedback"><HansalmaeIcon name="chat" size={18}/><div><b>선생님 피드백</b><p>{item.assistantFeedback}</p></div></section>}</div><footer><span>{reads[item.id]?`확인 완료 · ${formatRead(reads[item.id])}`:"리포트를 확인했다면 완료 표시를 남겨주세요."}</span>{!reads[item.id]&&<button type="button" disabled={confirming===item.id} onClick={()=>void confirm(item.id)}><HansalmaeIcon name="check" size={15}/>{confirming===item.id?"처리 중…":"확인했어요"}</button>}</footer></article>)}</div>}</section>
}
function Info({icon,title,text}:{icon:"chart"|"book";title:string;text:string}){return <section className="family-correction-info"><i><HansalmaeIcon name={icon} size={17}/></i><div><b>{title}</b><p>{text}</p></div></section>}
function cleanRange(value:string){return (value??"").replace(/^\[종류\][^\n]*\n?/,"").trim()}
function dateValue(v:string){return new Date(`${v}T12:00:00+09:00`)}
function formatDate(v:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"long",day:"numeric",weekday:"short"}).format(dateValue(v))}
function formatRead(v:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"numeric",day:"numeric",hour:"2-digit",minute:"2-digit",hour12:false}).format(new Date(v))}
function score(v:number){return Number.isInteger(Number(v))?String(Number(v)):Number(v).toFixed(1)}
