"use client";

import { useEffect,useMemo,useState } from "react";
import { createPortal } from "react-dom";
import { createSupabaseBrowserClient } from "./supabase";
import { CorrectionManagementBoard } from "./correction-management-board";
import { CorrectionWorkBoard } from "./correction-work-board";

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
          mounted.className="correction-hub-current-wrap correction-route-content";
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

  return createPortal(<>
    <CorrectionManagementBoard supabase={supabase}/>
    <CorrectionWorkBoard supabase={supabase}/>
  </>,host);
}
