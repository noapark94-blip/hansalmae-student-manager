"use client";

import { useEffect,useMemo,useState } from "react";
import { createPortal } from "react-dom";
import { createSupabaseBrowserClient } from "./supabase";
import { CorrectionManagementBoard } from "./correction-management-board";

export function CorrectionHubUnified(){
  const supabase=useMemo(()=>createSupabaseBrowserClient(),[]);
  const[host,setHost]=useState<HTMLElement|null>(null);

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
      }else if(!active){
        if(original)original.style.display="";
        if(mounted)mounted.remove();
        original=null;
        mounted=null;
        setHost(null);
      }
    };

    sync();
    const observer=new MutationObserver(sync);
    observer.observe(document.body,{subtree:true,childList:true,attributes:true,attributeFilter:["class"]});
    return()=>{
      observer.disconnect();
      if(original)original.style.display="";
      if(mounted)mounted.remove();
    };
  },[]);

  if(!host||!supabase)return null;

  return createPortal(
    <div className="correction-timetable-mode">
      <div className="page-heading correction-timetable-title">
        <div>
          <p className="eyebrow">한살매 첨삭 운영</p>
          <h1>첨삭 시간표</h1>
          <p>요일·시간 블록을 눌러 학생을 고정 배정하고, 이번 주만 변경·취소·추가할 수 있습니다.</p>
        </div>
      </div>
      <div className="correction-management-workspace">
        <CorrectionManagementBoard supabase={supabase}/>
      </div>
    </div>,
    host
  );
}
