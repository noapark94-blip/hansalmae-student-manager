"use client";

import { useCallback, useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import confirmStyles from "./message-confirm.module.css";

type Account = { id:string; displayName:string; email:string; role:string; isSelf:boolean; isActive:boolean };

export function AccountDeletionPanel({supabase}:{supabase:SupabaseClient}) {
  const [accounts,setAccounts]=useState<Account[]>([]);
  const [deleting,setDeleting]=useState("");
  const [message,setMessage]=useState("");
  const [deleteTarget,setDeleteTarget]=useState<Account|null>(null);
  const [deleteError,setDeleteError]=useState("");
  const load=useCallback(async()=>{const{data}=await supabase.rpc("admin_account_board");setAccounts(((data as {accounts?:Account[]}|null)?.accounts??[]).filter((item)=>!item.isSelf));},[supabase]);
  useEffect(()=>{void load();},[load]);
  const remove=async(account:Account)=>{setDeleting(account.id);setMessage("");setDeleteError("");const{error}=await supabase.functions.invoke("admin-delete-user",{body:{profileId:account.id}});if(error){let text=error.message;const context=(error as {context?:Response}).context;if(context){try{const body=await context.clone().json() as {error?:string};if(body.error)text=body.error;}catch{}}setDeleteError(text);}else{setMessage(`${account.displayName} 계정을 삭제했습니다.`);setDeleteTarget(null);await load();}setDeleting("");};
  return <><section className="panel account-deletion-panel"><header><div><h2>계정 삭제 관리</h2><p>사용하지 않는 계정을 정리합니다. 운영 기록이 있는 계정은 완전 삭제 대신 설정에서 로그인을 비활성화하세요.</p></div></header>{message&&<p className="account-delete-message">{message}</p>}<div>{accounts.map((account)=><article key={account.id}><span><b>{account.displayName}</b><small>{account.email} · {roleLabel(account.role)} · {account.isActive?"활성":"비활성"}</small></span><button type="button" disabled={Boolean(deleting)} onClick={()=>{setDeleteError("");setDeleteTarget(account)}}>{deleting===account.id?"확인 중…":"완전 삭제"}</button></article>)}</div></section>{deleteTarget?<div className={confirmStyles.backdrop} onMouseDown={event=>{if(event.target===event.currentTarget&&!deleting)setDeleteTarget(null)}}><section className={`${confirmStyles.dialog} ${confirmStyles.danger}`} role="alertdialog" aria-modal="true" aria-labelledby="account-delete-confirm-title"><button type="button" className={confirmStyles.close} aria-label="계정 삭제 확인창 닫기" disabled={Boolean(deleting)} onClick={()=>setDeleteTarget(null)}>×</button><div className={confirmStyles.icon} aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M5 7h14M9 7V4.5h6V7m-8 0 1 13h8l1-13M10 10.5v6M14 10.5v6"/></svg></div><p className={confirmStyles.eyebrow}>로그인 계정 완전 삭제</p><h3 id="account-delete-confirm-title">{deleteTarget.displayName} 계정을 삭제할까요?</h3><p className={confirmStyles.copy}>{deleteTarget.email}</p><div className={confirmStyles.stats}><span><small>역할</small><b>{roleLabel(deleteTarget.role)}</b></span><span><small>로그인</small><b>{deleteTarget.isActive?"활성":"비활성"}</b></span><span><small>처리 방식</small><b>완전 삭제</b></span></div><div className={confirmStyles.notice}><i aria-hidden="true">!</i><span>{deleteError||"연결된 수업·출결 기록이 있으면 삭제되지 않습니다."}</span></div><footer><button type="button" className={confirmStyles.cancel} disabled={Boolean(deleting)} onClick={()=>setDeleteTarget(null)}>돌아가기</button><button type="button" className={confirmStyles.primary} disabled={Boolean(deleting)} onClick={()=>void remove(deleteTarget)}>{deleting?"확인 중…":"계정 삭제"}</button></footer></section></div>:null}</>;
}

function roleLabel(role:string){return({admin:"관리자",teacher:"교사",assistant:"조교",manager:"실장님",student:"학생",guardian:"학부모"} as Record<string,string>)[role]??role;}
