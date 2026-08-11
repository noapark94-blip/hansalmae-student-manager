"use client";

import { useCallback, useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type Item={id:string;studentName:string;title:string;body:string;sourceType:"attendance"|"makeup";readAt:string|null;createdAt:string};
type Data={unreadCount:number;items:Item[]};

export function NotificationCenter({supabase}:{supabase:SupabaseClient}){
  const [open,setOpen]=useState(false);const [data,setData]=useState<Data>({unreadCount:0,items:[]});const [loading,setLoading]=useState(false);const [error,setError]=useState("");
  const load=useCallback(async()=>{const{data:next,error:loadError}=await supabase.rpc("family_notification_center");if(!loadError&&next)setData(next as Data);},[supabase]);
  useEffect(()=>{void load();},[load]);
  const show=async()=>{setOpen(true);setLoading(true);setError("");const{data:next,error:loadError}=await supabase.rpc("family_notification_center");if(loadError)setError("알림을 불러오지 못했습니다.");else setData(next as Data);setLoading(false);};
  const readAll=async()=>{const{error:saveError}=await supabase.rpc("mark_family_notifications_read",{p_notification_id:null});if(saveError)setError("알림을 읽음 처리하지 못했습니다.");else setData(current=>({...current,unreadCount:0,items:current.items.map(item=>({...item,readAt:item.readAt??new Date().toISOString()}))}));};
  return <><button className={`icon-button notification-button ${data.unreadCount?"has-unread":""}`} aria-label={`알림 ${data.unreadCount}개`} onClick={()=>void show()}>♢{data.unreadCount>0&&<i>{data.unreadCount>99?"99+":data.unreadCount}</i>}</button>{open&&<div className="notification-backdrop" onMouseDown={event=>{if(event.target===event.currentTarget)setOpen(false);}}><section className="notification-drawer"><header><div><p className="eyebrow">학생·학부모 알림</p><h2>알림센터</h2></div><button aria-label="닫기" onClick={()=>setOpen(false)}>×</button></header><div className="notification-toolbar"><span>읽지 않은 알림 {data.unreadCount}개</span>{data.unreadCount>0&&<button onClick={()=>void readAll()}>모두 읽음</button>}</div>{error&&<p className="form-error">{error}</p>}<div className="notification-list">{loading?<p>알림을 불러오는 중이에요…</p>:data.items.length===0?<p>새로운 알림이 없습니다.</p>:data.items.map(item=><article key={item.id} className={item.readAt?"":"unread"}><i>{item.sourceType==="attendance"?"✓":"↻"}</i><span><b>{item.title}</b><small>{item.studentName} · {formatDate(item.createdAt)}</small><p>{item.body}</p></span></article>)}</div></section></div>}</>;
}
function formatDate(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"short",day:"numeric",hour:"2-digit",minute:"2-digit"}).format(new Date(value));}
