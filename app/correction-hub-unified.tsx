"use client";

import { useEffect,useMemo,useState } from "react";
import { createPortal } from "react-dom";
import { createSupabaseBrowserClient } from "./supabase";

type Assignment={id:string;studentId:string;studentName:string;school:string|null;grade:string|null;subject:"국어"|"영어"|"수학";weekday:number;startTime:string;endTime:string};
type Board={assignments:Assignment[]};
const days=["월","화","수","목","금","토","일"];
const weekdaySlots=[["14:30","16:00"],["16:00","17:30"],["17:30","19:00"],["19:00","20:30"],["20:30","22:00"]] as const;
const weekendSlots=[["09:30","11:00"],["11:00","12:30"],["12:30","14:00"],["14:00","15:30"],["15:30","17:00"]] as const;

export function CorrectionHubUnified(){
  const supabase=useMemo(()=>createSupabaseBrowserClient(),[]);
  const[host,setHost]=useState<HTMLElement|null>(null);
  const[data,setData]=useState<Board|null>(null);
  const[loading,setLoading]=useState(false);

  useEffect(()=>{
    let original:HTMLElement|null=null;
    let mounted:HTMLElement|null=null;
    const sync=()=>{
      const buttons=Array.from(document.querySelectorAll<HTMLButtonElement>(".schedule-tabs button"));
      const active=buttons.find(button=>button.classList.contains("active")&&button.textContent?.includes("첨삭 시간표"));
      const panels=Array.from(document.querySelectorAll<HTMLElement>("section.hub-panel"));
      const panel=panels.find(item=>item.textContent?.includes("고정 첨삭 시간표"))??null;
      if(active&&panel){
        if(original!==panel){
          if(original)original.style.display="";
          if(mounted)mounted.remove();
          original=panel;
          original.style.display="none";
          mounted=document.createElement("div");
          mounted.className="correction-hub-current-wrap";
          panel.insertAdjacentElement("afterend",mounted);
          setHost(mounted);
        }
      }else{
        if(original)original.style.display="";
        if(mounted)mounted.remove();
        original=null;mounted=null;setHost(null);
      }
    };
    sync();
    const observer=new MutationObserver(sync);
    observer.observe(document.body,{subtree:true,childList:true,attributes:true,attributeFilter:["class"]});
    return()=>{observer.disconnect();if(original)original.style.display="";if(mounted)mounted.remove();};
  },[]);

  useEffect(()=>{
    if(!host||!supabase)return;
    let alive=true;
    setLoading(true);
    void supabase.rpc("correction_management_board_v2",{p_anchor:koreaToday()}).then(({data:next})=>{
      if(!alive)return;
      setData((next??{assignments:[]}) as Board);setLoading(false);
    });
    return()=>{alive=false};
  },[host,supabase]);

  if(!host)return null;
  return createPortal(<section className="panel hub-panel correction-hub-current">
    <div className="hub-toolbar"><div><h2>고정 첨삭 시간표</h2><p>현재 첨삭 관리에서 사용하는 정규 배정과 동일한 시간표입니다. 이번 주 변경·취소·추가는 여기에 반영하지 않습니다.</p></div><a className="primary hub-add" href="/corrections">첨삭 배정 관리</a></div>
    {loading?<p className="settings-empty">첨삭 시간표를 불러오는 중이에요…</p>:<div className="correction-week-board correction-hub-fixed-board">{days.map((day,index)=>{
      const weekday=index+1;const slots=weekday<=5?weekdaySlots:weekendSlots;
      const count=(data?.assignments??[]).filter(item=>item.weekday===weekday).length;
      return <section key={day} className="correction-day mobile-active"><header><span><b>{day}요일</b></span><em>{count}명</em></header><div className="correction-slot-list">{slots.map(([start,end])=>{
        const rows=(data?.assignments??[]).filter(item=>item.weekday===weekday&&item.startTime.slice(0,5)===start);
        return <article className="correction-slot" key={start}><div className="correction-slot-time"><b>{start}</b><span>– {end}</span></div><div className="correction-slot-content">{rows.length?<div className="correction-slot-students">{rows.map(row=><div key={row.id} className={`correction-student subject-${row.subject}`}><span><b>{row.studentName}</b><small>{[row.grade,row.subject].filter(Boolean).join(" · ")}</small></span></div>)}</div>:<p className="correction-slot-empty">배정 없음</p>}</div></article>;
      })}</div></section>;
    })}</div>}
  </section>,host);
}

function koreaToday(){return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date());}
