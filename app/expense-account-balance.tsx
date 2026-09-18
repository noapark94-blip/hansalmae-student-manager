"use client";
import {useEffect,useRef,useState,type FormEvent} from "react";
import type {SupabaseClient} from "@supabase/supabase-js";
type Balance={amount:number;checked_on:string;version:number};
const today=()=>new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date());
export function ExpenseAccountBalance({supabase}:{supabase:SupabaseClient}){
 const [balance,setBalance]=useState<Balance|null>(null),[loading,setLoading]=useState(true),[error,setError]=useState(""),[editing,setEditing]=useState(false),[saving,setSaving]=useState(false);
 const [amount,setAmount]=useState(""),[date,setDate]=useState(today),[revision,setRevision]=useState(0),[notice,setNotice]=useState("");
 const input=useRef<HTMLInputElement>(null),trigger=useRef<HTMLButtonElement>(null);
 useEffect(()=>{let cancelled=false;setLoading(true);setError("");
  void (async()=>{try{const {data,error:failure}=await supabase.rpc("admin_account_balance");if(failure)throw failure;if(!cancelled)setBalance(data as Balance|null);}catch(err){if(!cancelled)setError((err as {message?:string}).message||"계좌 잔액을 불러오지 못했습니다.");}finally{if(!cancelled)setLoading(false);}})();
  return()=>{cancelled=true;};
 },[supabase,revision]);
 useEffect(()=>{if(editing)input.current?.focus();},[editing]);
 const close=()=>{setEditing(false);setError("");trigger.current?.focus();};
 const save=async(event:FormEvent)=>{event.preventDefault();if(saving)return;
  const value=Number(amount);
  if(!amount||!Number.isSafeInteger(value)||value<0||value>999999999999||!date||date>today()){setError("잔액과 확인 기준일을 확인해 주세요.");return;}
  setSaving(true);setError("");
  try{const {data,error:failure}=await supabase.rpc("admin_save_account_balance",{p_amount:value,p_checked_on:date,p_expected_version:balance?.version??null});if(failure)throw failure;setBalance(data as Balance);setEditing(false);setNotice("확인한 계좌 잔액을 저장했습니다.");trigger.current?.focus();}
  catch(err){setError((err as {message?:string}).message||"계좌 잔액을 저장하지 못했습니다.");}finally{setSaving(false);}
 };
 return <section className="expense-balance" aria-label="최근 확인 계좌 잔액">
  <div className="expense-balance-display"><div><h2>최근 확인 계좌 잔액 <span>직접 입력</span></h2><p>{balance?balance.checked_on.replaceAll("-",". ")+". 기준 · 조회 월과 별도로 표시":"실제 계좌에서 확인한 잔액을 기록해 주세요."}</p></div><strong>{loading?"불러오는 중…":balance?Number(balance.amount).toLocaleString("ko-KR")+"원":"미등록"}</strong><button type="button" className="expense-outline" ref={trigger} disabled={loading||saving} onClick={()=>{setAmount(balance?String(balance.amount):"");setDate(today());setEditing(true);setNotice("");setError("");}}>{balance?"잔액 수정":"잔액 입력"}</button></div>
  <p className="expense-balance-hint">수납·지출 합계에 더하지 않으며, 입력한 잔액은 자동으로 변하지 않습니다.</p>
  {editing&&<form onSubmit={save} onKeyDown={e=>{if(e.key==="Escape"&&!saving){e.preventDefault();e.stopPropagation();close();}}}>
   <label>확인한 잔액<div><input ref={input} required inputMode="numeric" value={amount?Number(amount).toLocaleString("ko-KR"):""} disabled={saving} onChange={e=>setAmount(e.target.value.replace(/[^0-9]/g,"").slice(0,12))} placeholder="0"/><span>원</span></div></label>
   <label>확인 기준일<input type="date" required value={date} min="1900-01-01" max={today()} disabled={saving} onChange={e=>setDate(e.target.value)}/></label>
   <div className="expense-balance-actions"><button type="button" className="expense-outline" disabled={saving} onClick={close}>취소</button><button className="expense-primary" disabled={saving}>{saving?"저장 중…":"잔액 저장"}</button></div>
  </form>}
  {error&&<div className="expense-balance-error" role="alert">{error}<button type="button" disabled={saving||loading} onClick={()=>{setEditing(false);setRevision(v=>v+1);}}>최신 잔액 불러오기</button></div>}
  {notice&&<p className="expense-balance-notice" role="status">{notice}</p>}
 </section>;
}
