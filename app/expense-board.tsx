"use client";

import { useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

const categories = ["임대료","급여","관리비","교재비","광고비","비품","기타"] as const;
const methods: Record<string,string> = {transfer:"계좌이체",card:"카드",cash:"현금",other:"기타"};
type Expense = {id:string;spent_on:string;category:string;vendor:string;amount:number;payment_method:string;memo:string;receipt_path:string|null;receipt_name:string|null;version:number};
type Board = {items:Expense[];receipts:number};
type Draft = {id:string;spent_on:string;category:string;vendor:string;amount:string;payment_method:string;memo:string;receipt_path:string|null;receipt_name:string|null;version:number|null};
const won = (value:number)=>value.toLocaleString("ko-KR")+"원";
const today = ()=>new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date());
function nextMonth(month:string,offset:number){const [y,m]=month.split("-").map(Number);const date=new Date(Date.UTC(y,m-1+offset,1));return date.toISOString().slice(0,7);}
function copyDate(date:string){const month=nextMonth(date.slice(0,7),1);const [y,m]=month.split("-").map(Number);const day=Math.min(Number(date.slice(8)),new Date(Date.UTC(y,m,0)).getUTCDate());return month+"-"+String(day).padStart(2,"0");}
const monthLabel=(month:string)=>month.replace("-","년 ")+"월";
function emptyDraft(month:string):Draft{return {id:crypto.randomUUID(),spent_on:today().startsWith(month)?today():month+"-01",category:"기타",vendor:"",amount:"",payment_method:"transfer",memo:"",receipt_path:null,receipt_name:null,version:null};}
function message(error:unknown){return (error as {message?:string})?.message||"처리하지 못했습니다. 다시 시도해 주세요.";}

export function ExpenseBoard({supabase}:{supabase:SupabaseClient}){
  const [month,setMonth]=useState(()=>today().slice(0,7));
  const [data,setData]=useState<Board|null>(null);
  const [loading,setLoading]=useState(true);
  const [error,setError]=useState("");
  const [notice,setNotice]=useState("");
  const [search,setSearch]=useState("");
  const [category,setCategory]=useState("전체");
  const [draft,setDraft]=useState<Draft|null>(null);
  const [removing,setRemoving]=useState<Expense|null>(null);
  const [busy,setBusy]=useState(false);
  const [receiptBusy,setReceiptBusy]=useState<string|null>(null);
  const request=useRef(0);
  const load=useCallback(async()=>{
    const id=++request.current;setLoading(true);setError("");
    try{
      const {data:result,error:failure}=await supabase.rpc("admin_expense_board",{p_month:month+"-01"});
      if(id!==request.current)return;
      if(failure)throw failure;
      setData(result as Board);
    }catch(err){if(id===request.current){setError(message(err));setData(null);}}
    finally{if(id===request.current)setLoading(false);}
  },[month,supabase]);
  useEffect(()=>{void load();return()=>{request.current++;};},[load]);
  const items=data?.items??[];
  const total=items.reduce((sum,item)=>sum+item.amount,0);
  const visible=items.filter(item=>(category==="전체"||item.category===category)&&[item.vendor,item.memo,item.category].join(" ").toLowerCase().includes(search.trim().toLowerCase()));
  const shownTotal=visible.reduce((sum,item)=>sum+item.amount,0);
  const changeMonth=(value:string)=>{if(!/^\d{4}-\d{2}$/.test(value)||Number(value.slice(0,4))<1900||Number(value.slice(0,4))>9998)return;setMonth(value);setNotice("");};
  const remove=async()=>{
    if(!removing||busy)return;setBusy(true);setError("");
    try{const {error:failure}=await supabase.rpc("admin_delete_expense",{p_id:removing.id,p_expected_version:removing.version});if(failure)throw failure;setRemoving(null);setNotice("지출 내역을 삭제했습니다.");await load();}
    catch(err){setError(message(err));}finally{setBusy(false);}
  };
  const openReceipt=async(item:Expense)=>{
    if(!item.receipt_path)return;setReceiptBusy(item.id);setError("");
    try{
      const {data:blob,error:failure}=await supabase.storage.from("expense-receipts").download(item.receipt_path);
      if(failure||!blob)throw failure||new Error("영수증을 불러오지 못했습니다.");
      const url=URL.createObjectURL(blob);const link=document.createElement("a");link.href=url;link.download=item.receipt_name||"영수증";link.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
    }catch(err){setError(message(err));}finally{setReceiptBusy(null);}
  };
  return <section className="expense-board">
    <header className="expense-heading"><div><p>관리자 전용</p><h1>지출 관리</h1><span>학원 운영에 사용한 금액을 월별로 기록합니다.</span></div><button className="expense-primary" onClick={()=>{setNotice("");setDraft(emptyDraft(month));}}>＋ 지출 등록</button></header>
    <div className="expense-month-bar"><div className="expense-month-picker"><button aria-label="이전 달" onClick={()=>changeMonth(nextMonth(month,-1))}>‹</button><label><span className="expense-sr-only">조회 월</span><input type="month" value={month} min="1900-01" max="9998-12" onChange={e=>changeMonth(e.target.value)}/></label><button aria-label="다음 달" onClick={()=>changeMonth(nextMonth(month,1))}>›</button></div><span>실제 수납일 · 지급일 기준</span><button className="expense-text-button" onClick={()=>void load()} disabled={loading}>새로고침</button></div>
    <div className="expense-summary" aria-busy={loading}>
      <article className="expense-summary-main"><span>이번 달 지출</span><strong>{loading||!data?"—":won(total)}</strong><small>{loading?"내역 확인 중":items.length+"건의 지출"}</small></article>
      <article><span>실제 수납액</span><strong>{loading||!data?"—":won(Number(data.receipts))}</strong><small>선택한 달에 실제로 받은 원비</small></article>
      <article><span>수납 − 지출</span><strong className={data&&Number(data.receipts)-total<0?"expense-negative":""}>{loading||!data?"—":won(Number(data.receipts)-total)}</strong><small>등록된 지출 기준 차액</small></article>
    </div>
    {error&&<p className="expense-error" role="alert">{error}</p>}
    {notice&&<p className="expense-notice" role="status">{notice}</p>}
    <section className="expense-ledger"><header><div><h2>지출 내역</h2><p>{monthLabel(month)}의 운영 기록</p></div><label className="expense-search"><span className="expense-sr-only">사용처·비고 검색</span><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="사용처·비고 검색"/></label></header>
      <div className="expense-category-tabs" role="group" aria-label="지출 분류">{["전체",...categories].map(value=><button key={value} aria-pressed={category===value} className={category===value?"active":""} onClick={()=>setCategory(value)}>{value}</button>)}</div>
      <div className="expense-list-caption"><span>{visible.length}건</span><strong>합계 {won(shownTotal)}</strong></div>
      <div className="expense-table-head"><span>지급일</span><span>분류</span><span>사용처 · 비고</span><span>금액</span><span>결제 방법</span><span>관리</span></div>
      {loading?<p className="expense-empty">지출 내역을 불러오는 중이에요.</p>:!data?<p className="expense-empty">내역을 불러오지 못했습니다. 새로고침해 주세요.</p>:!visible.length?<div className="expense-empty"><b>{items.length?"검색 조건에 맞는 지출이 없습니다.":"아직 등록된 지출이 없습니다."}</b><p>{items.length?"다른 검색어나 분류를 선택해 주세요.":"임대료, 급여, 교재비부터 간편하게 기록해 보세요."}</p>{!items.length&&<button className="expense-outline" onClick={()=>setDraft(emptyDraft(month))}>첫 지출 등록</button>}</div>:visible.map(item=><article className="expense-row" key={item.id}>
        <time dateTime={item.spent_on}>{item.spent_on.slice(5).replace("-",". ")}.</time><span className="expense-category">{item.category}</span><div className="expense-description"><b>{item.vendor}</b>{item.memo&&<p>{item.memo}</p>}{item.receipt_path&&<button disabled={receiptBusy===item.id} onClick={()=>void openReceipt(item)}>{receiptBusy===item.id?"불러오는 중…":"↗ 영수증"}</button>}</div><strong className="expense-amount">{won(item.amount)}</strong><span className="expense-method">{methods[item.payment_method]??item.payment_method}</span>
        <div className="expense-row-actions"><button onClick={()=>setDraft({...item,amount:String(item.amount)})}>수정</button><details><summary aria-label={item.vendor+" 추가 작업"}>⋯</summary><div><button onClick={()=>setDraft({...item,id:crypto.randomUUID(),spent_on:copyDate(item.spent_on),amount:String(item.amount),version:null,receipt_path:null,receipt_name:null})}>다음 달에 복사</button><button className="expense-delete" onClick={()=>{setError("");setRemoving(item);}}>삭제</button></div></details></div>
      </article>)}
    </section>
    {draft&&<ExpenseEditor supabase={supabase} initial={draft} onClose={()=>setDraft(null)} onSaved={async(savedMonth)=>{setDraft(null);setNotice("지출 내역을 저장했습니다.");if(savedMonth!==month)setMonth(savedMonth);else await load();}}/>}
    {removing&&<div className="expense-overlay"><section className="expense-dialog expense-confirm" role="dialog" aria-modal="true" aria-labelledby="expense-delete-title"><header><div><h2 id="expense-delete-title">지출을 삭제할까요?</h2><p>{removing.vendor} · {won(removing.amount)}</p></div></header><div className="expense-dialog-body"><p>삭제하면 월별 지출 합계에서 제외됩니다.</p>{error&&<p className="expense-error" role="alert">{error}</p>}</div><footer><button className="expense-outline" disabled={busy} onClick={()=>setRemoving(null)}>취소</button><button className="expense-primary" disabled={busy} onClick={()=>void remove()}>{busy?"삭제 중…":"삭제"}</button></footer></section></div>}
  </section>;
}

function ExpenseEditor({supabase,initial,onClose,onSaved}:{supabase:SupabaseClient;initial:Draft;onClose:()=>void;onSaved:(month:string)=>Promise<void>}){
  const [draft,setDraft]=useState(initial),[file,setFile]=useState<File|null>(null),[busy,setBusy]=useState(false),[error,setError]=useState("");
  const dialog=useRef<HTMLFormElement>(null);
  useEffect(()=>{
    const previous=document.activeElement as HTMLElement|null;
    Array.from(dialog.current?.querySelectorAll<HTMLElement>(".expense-date-trigger,input")??[]).find(node=>node.getClientRects().length>0)?.focus();
    return()=>previous?.focus();
  },[]);
  const patch=(value:Partial<Draft>)=>setDraft(current=>({...current,...value}));
  const submit=async(event:FormEvent)=>{
    event.preventDefault();if(busy)return;setError("");
    const amount=Number(draft.amount.replace(/,/g,""));
    if(!Number.isSafeInteger(amount)||amount<=0||amount>2147483647){setError("금액을 1원 이상, 2,147,483,647원 이하로 입력해 주세요.");return;}
    if(!draft.vendor.trim()||!draft.spent_on){setError("지급일과 사용처를 입력해 주세요.");return;}
    setBusy(true);
    let uploaded:string|null=null;
    try{
      let receiptPath=draft.receipt_path,receiptName=draft.receipt_name;
      if(file){
        const ext:Record<string,string>={"image/jpeg":"jpg","image/png":"png","image/webp":"webp","application/pdf":"pdf"};
        if(!ext[file.type]||file.size>10485760)throw new Error("영수증은 JPG·PNG·WEBP·PDF 파일로 10MB까지 첨부할 수 있습니다.");
        const path=draft.id+"/"+crypto.randomUUID()+"."+ext[file.type];
        const {error:uploadError}=await supabase.storage.from("expense-receipts").upload(path,file,{contentType:file.type,upsert:false});
        if(uploadError)throw uploadError;uploaded=path;receiptPath=path;receiptName=file.name;
      }
      const {error:saveError}=await supabase.rpc("admin_save_expense",{p_id:draft.id,p_expected_version:draft.version,p_values:{spent_on:draft.spent_on,category:draft.category,vendor:draft.vendor.trim(),amount,payment_method:draft.payment_method,memo:draft.memo,receipt_path:receiptPath,receipt_name:receiptName}});
      if(saveError)throw saveError;
      uploaded=null;
      await onSaved(draft.spent_on.slice(0,7));
    }catch(err){
      if(uploaded)await supabase.storage.from("expense-receipts").remove([uploaded]);
      setError(message(err));
    }finally{setBusy(false);}
  };
  return <div className="expense-overlay"><form ref={dialog} className="expense-dialog" role="dialog" aria-modal="true" aria-labelledby="expense-editor-title" onSubmit={submit} onKeyDown={event=>{
    if(event.key==="Escape"&&!busy){event.stopPropagation();onClose();}
    if(event.key==="Tab"){const nodes=dialog.current?.querySelectorAll<HTMLElement>('button:not(:disabled),input:not(:disabled),select:not(:disabled),textarea:not(:disabled),[tabindex="0"]');if(!nodes?.length)return;const first=nodes[0],last=nodes[nodes.length-1];if(event.shiftKey&&document.activeElement===first){event.preventDefault();last.focus();}else if(!event.shiftKey&&document.activeElement===last){event.preventDefault();first.focus();}}
  }}>
    <header><div><p>학원 운영 기록</p><h2 id="expense-editor-title">{initial.version?"지출 내역 수정":"지출 등록"}</h2><span>실제로 지급한 날짜와 금액을 입력해 주세요.</span></div><button type="button" aria-label="닫기" disabled={busy} onClick={onClose}>×</button></header>
    <div className="expense-dialog-body"><div className="expense-form-grid">
      <ExpenseDatePicker value={draft.spent_on} disabled={busy} onChange={spent_on=>patch({spent_on})}/>
      <label>분류<select value={draft.category} disabled={busy} onChange={e=>patch({category:e.target.value})}>{categories.map(value=><option key={value}>{value}</option>)}</select></label>
      <label className="expense-full">사용처<input required maxLength={120} value={draft.vendor} disabled={busy} onChange={e=>patch({vendor:e.target.value})} placeholder="예: 9월 임대료, 교재 구입"/></label>
      <label>지출 금액<div className="expense-money-input"><input required inputMode="numeric" value={draft.amount?Number(draft.amount.replace(/,/g,"")).toLocaleString("ko-KR"):""} disabled={busy} onChange={e=>patch({amount:e.target.value.replace(/[^0-9]/g,"").slice(0,10)})} placeholder="0"/><span>원</span></div></label>
      <label>결제 방법<select value={draft.payment_method} disabled={busy} onChange={e=>patch({payment_method:e.target.value})}>{Object.entries(methods).map(([value,label])=><option value={value} key={value}>{label}</option>)}</select></label>
      <label className="expense-full">비고 <small>선택</small><textarea rows={3} maxLength={2000} value={draft.memo} disabled={busy} onChange={e=>patch({memo:e.target.value})} placeholder="지출 관련 참고 사항을 적어 주세요."/></label>
      <div className="expense-full expense-attachment"><label htmlFor="expense-file">영수증 <small>선택</small></label><p>사진 또는 PDF · 최대 10MB</p><input id="expense-file" type="file" accept="image/jpeg,image/png,image/webp,application/pdf" disabled={busy} onChange={e=>setFile(e.target.files?.[0]??null)}/>{(file||draft.receipt_name)&&<div><span>{file?.name??draft.receipt_name}</span><button type="button" disabled={busy} onClick={()=>{setFile(null);patch({receipt_path:null,receipt_name:null});const input=dialog.current?.querySelector<HTMLInputElement>("#expense-file");if(input)input.value="";}}>첨부 해제</button></div>}</div>
    </div>{error&&<p className="expense-error" role="alert">{error}</p>}</div>
    <footer><button type="button" className="expense-outline" disabled={busy} onClick={onClose}>취소</button><button className="expense-primary" disabled={busy}>{busy?"저장 중…":"지출 저장"}</button></footer>
  </form></div>;
}

function ExpenseDatePicker({value,onChange,disabled}:{value:string;onChange:(value:string)=>void;disabled:boolean}){
  const [open,setOpen]=useState(false);
  const [month,setMonth]=useState(value.slice(0,7)||today().slice(0,7));
  const root=useRef<HTMLDivElement>(null);
  const trigger=useRef<HTMLButtonElement>(null);
  useEffect(()=>{
    if(!open)return;
    const outside=(event:PointerEvent)=>{if(!root.current?.contains(event.target as Node))setOpen(false);};
    document.addEventListener("pointerdown",outside);
    return()=>document.removeEventListener("pointerdown",outside);
  },[open]);
  const [year,number]=month.split("-").map(Number);
  const offset=new Date(Date.UTC(year,number-1,1)).getUTCDay();
  const count=new Date(Date.UTC(year,number,0)).getUTCDate();
  const choose=(date:string)=>{onChange(date);setOpen(false);trigger.current?.focus();};
  return <div className="expense-date-field" ref={root} onKeyDown={event=>{
    if(open&&event.key==="Escape"){event.preventDefault();event.stopPropagation();setOpen(false);trigger.current?.focus();}
  }}>
    <label className="expense-date-native">지급일<input type="date" required value={value} disabled={disabled} onChange={event=>onChange(event.target.value)}/></label>
    <div className="expense-date-mobile">
      <span>지급일</span>
      <button type="button" ref={trigger} className="expense-date-trigger" disabled={disabled} aria-label={"지급일 "+value} aria-expanded={open} onClick={()=>{if(!open)setMonth(value.slice(0,7)||today().slice(0,7));setOpen(current=>!current);}}><span>{value||"날짜 선택"}</span><span aria-hidden="true">▦</span></button>
      {open&&<div className="expense-date-popover" role="group" aria-label="지급일 선택">
        <div className="expense-date-nav"><button type="button" disabled={disabled||month<="1900-01"} aria-label="이전 달" onClick={()=>setMonth(nextMonth(month,-1))}>‹</button><strong aria-live="polite">{monthLabel(month)}</strong><button type="button" disabled={disabled||month>="9998-12"} aria-label="다음 달" onClick={()=>setMonth(nextMonth(month,1))}>›</button></div>
        <div className="expense-date-grid">
          {["일","월","화","수","목","금","토"].map(day=><span key={day}>{day}</span>)}
          {Array.from({length:offset},(_,i)=><span key={"blank"+i}/>)}
          {Array.from({length:count},(_,i)=>{const date=month+"-"+String(i+1).padStart(2,"0");return <button type="button" key={date} disabled={disabled} aria-label={date} aria-pressed={value===date} aria-current={date===today()?"date":undefined} onClick={()=>choose(date)}>{i+1}</button>;})}
        </div>
        <div className="expense-date-footer"><button type="button" disabled={disabled} onClick={()=>choose(today())}>오늘 선택</button><button type="button" onClick={()=>{setOpen(false);trigger.current?.focus();}}>닫기</button></div>
      </div>}
    </div>
  </div>;
}
