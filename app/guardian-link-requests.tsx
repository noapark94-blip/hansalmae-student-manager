"use client";

import { useCallback,useEffect,useMemo,useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type RequestRow={id:string;guardianName:string;guardianPhone:string;studentName:string;school:string|null;grade:string|null;createdAt:string};
type Student={id:string;name:string;school:string|null;grade:string|null};
type Board={requests:RequestRow[];students:Student[]};

export function GuardianLinkRequests({supabase}:{supabase:SupabaseClient}){
  const[data,setData]=useState<Board>({requests:[],students:[]}),[loading,setLoading]=useState(true),[processing,setProcessing]=useState(""),[message,setMessage]=useState("");
  const[selected,setSelected]=useState<Record<string,string>>({});
  const load=useCallback(async()=>{setLoading(true);const{data:next,error}=await supabase.rpc("admin_guardian_link_request_board");if(!error){const board=next as Board;setData(board);setSelected(current=>Object.fromEntries(board.requests.map(row=>[row.id,current[row.id]||bestMatch(row,board.students)])))}setLoading(false)},[supabase]);
  useEffect(()=>{void load()},[load]);
  const resolve=async(row:RequestRow,action:"approve"|"reject")=>{const studentId=selected[row.id]||"";if(action==="approve"&&!studentId){setMessage("연결할 학생을 선택해 주세요.");return}if(!confirm(action==="approve"?`${row.guardianName} 학부모님을 선택한 학생과 연결할까요?`:`${row.guardianName} 학부모님의 요청을 거절할까요?`))return;setProcessing(row.id);setMessage("");const{error}=await supabase.rpc("admin_resolve_guardian_link_request",{p_request_id:row.id,p_action:action,p_student_id:studentId||null});setMessage(error?error.message:action==="approve"?"학부모 계정을 승인하고 자녀를 연결했습니다.":"연결 요청을 거절했습니다.");if(!error)await load();setProcessing("")};
  const count=data.requests.length;
  const options=useMemo(()=>new Map(data.requests.map(row=>[row.id,ranked(row,data.students)])),[data]);
  return <section className="panel guardian-request-panel"><header><div><p className="eyebrow">관리자 확인 필요</p><h2>학부모 자녀 연결 요청</h2><span>초대코드 없이 가입한 학부모와 실제 학생을 확인해 주세요.</span></div><em>{count}건 대기</em></header>{message&&<p className="password-reset-message">{message}</p>}{loading?<p className="settings-empty">연결 요청을 확인하는 중이에요…</p>:!count?<p className="settings-empty">대기 중인 학부모 연결 요청이 없습니다.</p>:<div className="guardian-request-list">{data.requests.map(row=><article key={row.id}><div className="guardian-request-person"><b>{row.guardianName}</b><small>{row.guardianPhone} · {formatTime(row.createdAt)}</small><span>요청 자녀: <strong>{row.studentName}</strong>{[row.school,row.grade].filter(Boolean).length?` · ${[row.school,row.grade].filter(Boolean).join(" · ")}`:""}</span></div><label>연결할 학생<select value={selected[row.id]||""} onChange={event=>setSelected(current=>({...current,[row.id]:event.target.value}))}><option value="">학생을 선택해 주세요</option>{(options.get(row.id)??data.students).map(student=><option value={student.id} key={student.id}>{student.name}{student.school?` · ${student.school}`:""}{student.grade?` · ${student.grade}`:""}</option>)}</select></label><div><button type="button" className="secondary-button" disabled={processing===row.id} onClick={()=>void resolve(row,"reject")}>거절</button><button type="button" className="primary" disabled={processing===row.id||!selected[row.id]} onClick={()=>void resolve(row,"approve")}>{processing===row.id?"처리 중…":"승인·연결"}</button></div></article>)}</div>}</section>;
}
function score(row:RequestRow,student:Student){let value=0;if(student.name===row.studentName)value+=100;if(row.school&&student.school===row.school)value+=20;if(row.grade&&student.grade===row.grade)value+=10;return value}
function ranked(row:RequestRow,students:Student[]){return [...students].sort((a,b)=>score(row,b)-score(row,a)||a.name.localeCompare(b.name,"ko"))}
function bestMatch(row:RequestRow,students:Student[]){const matches=students.filter(student=>student.name===row.studentName&&(row.school?student.school===row.school:true)&&(row.grade?student.grade===row.grade:true));return matches.length===1?matches[0].id:""}
function formatTime(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"short",day:"numeric",hour:"2-digit",minute:"2-digit",hour12:false}).format(new Date(value))}
