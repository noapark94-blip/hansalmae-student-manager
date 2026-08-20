"use client";

import { useEffect } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type ChangeInfo={kind:"move"|"extra";targetDay:number;targetTime:string;originDay?:number;originTime?:string};

export function CorrectionOperationSync({supabase:_supabase}:{supabase:SupabaseClient}){
  useEffect(()=>{
    let frame=0;

    const studentKey=(card:Element)=>{
      const name=card.querySelector("b")?.textContent?.trim()??"";
      const meta=card.querySelector("small")?.textContent?.trim()??"";
      const subject=meta.split("·").map(value=>value.trim()).filter(Boolean).at(-1)??"";
      return `${name}|${subject}`;
    };

    const dayIndex=(card:Element)=>{
      const day=card.closest(".correction-day");
      const board=day?.parentElement;
      if(!day||!board)return -1;
      return [...board.querySelectorAll(":scope > .correction-day")].indexOf(day);
    };

    const slotTime=(card:Element)=>card.closest(".correction-slot")?.querySelector(".correction-slot-time b")?.textContent?.trim()??"";

    const ensureBadge=(target:HTMLElement,kind:"move"|"extra",detail=false)=>{
      let badge=target.querySelector<HTMLElement>(":scope > .correction-change-badge");
      if(!badge){badge=document.createElement("span");badge.className="correction-change-badge";target.appendChild(badge);}
      badge.className=`correction-change-badge ${detail?"detail ":""}${kind}`;
      badge.textContent=kind==="move"?(detail?"변경 일정":"변경"):(detail?"추가 첨삭":"추가");
    };

    const clearBadge=(target:HTMLElement)=>target.querySelector(":scope > .correction-change-badge")?.remove();

    const apply=()=>{
      const board=document.querySelector<HTMLElement>(".correction-week-board");
      if(!board)return;

      const changes=new Map<string,ChangeInfo>();
      const origins=new Map<string,{day:number;time:string}>();

      board.querySelectorAll<HTMLElement>(".correction-student.ghost").forEach(card=>{
        origins.set(studentKey(card),{day:dayIndex(card),time:slotTime(card)});
      });

      board.querySelectorAll<HTMLElement>(".correction-student.moved").forEach(card=>{
        const key=studentKey(card),origin=origins.get(key);
        changes.set(key,{kind:"move",targetDay:dayIndex(card),targetTime:slotTime(card),originDay:origin?.day,originTime:origin?.time});
      });
      board.querySelectorAll<HTMLElement>(".correction-student.extra").forEach(card=>{
        changes.set(studentKey(card),{kind:"extra",targetDay:dayIndex(card),targetTime:slotTime(card)});
      });

      board.querySelectorAll<HTMLElement>(".correction-day").forEach(day=>{
        const visible=day.querySelectorAll(".correction-student.fixed,.correction-student.ghost").length;
        const badge=day.querySelector<HTMLElement>(":scope > header > em");
        if(badge)badge.textContent=`${visible}명`;
      });

      const weekButtons=[...document.querySelectorAll<HTMLButtonElement>(".correction-week-strip > button")];
      weekButtons.forEach((button,index)=>{
        button.querySelectorAll<HTMLElement>("div > em").forEach(nameEl=>{
          const name=(nameEl.childNodes[0]?.textContent??nameEl.textContent??"").trim();
          const candidates=[...changes.entries()].filter(([key,info])=>key.startsWith(`${name}|`)&&info.targetDay===index);
          const change=candidates[0]?.[1];
          if(change)ensureBadge(nameEl,change.kind);else clearBadge(nameEl);
        });
      });

      const selectedDay=weekButtons.findIndex(button=>button.classList.contains("active"));
      document.querySelectorAll<HTMLElement>(".correction-learning-rows article").forEach(article=>{
        const student=article.querySelector<HTMLElement>(".learning-student");
        const name=student?.querySelector("button b")?.textContent?.trim()??"";
        const meta=student?.querySelector("small")?.textContent?.trim()??"";
        const subject=[...changes.keys()].find(key=>key.startsWith(`${name}|`)&&meta.includes(key.split("|")[1]))?.split("|")[1]??"";
        const change=changes.get(`${name}|${subject}`);
        if(!student||!change||change.targetDay!==selectedDay){
          if(student){clearBadge(student);student.querySelector(":scope > .correction-change-origin")?.remove();}
          return;
        }
        ensureBadge(student,change.kind,true);
        let detail=student.querySelector<HTMLElement>(":scope > .correction-change-origin");
        if(!detail){detail=document.createElement("small");detail.className="correction-change-origin";student.appendChild(detail);}
        if(change.kind==="move"&&change.originDay!=null){
          const days=["월","화","수","목","금","토","일"];
          detail.textContent=`기존 ${days[change.originDay]} ${change.originTime} → ${days[change.targetDay]} ${change.targetTime}`;
        }else detail.textContent="정규 일정 외 추가 첨삭";
      });
    };

    const schedule=()=>{
      cancelAnimationFrame(frame);
      frame=requestAnimationFrame(apply);
    };

    schedule();
    const observer=new MutationObserver(schedule);
    observer.observe(document.body,{childList:true,subtree:true});
    return()=>{cancelAnimationFrame(frame);observer.disconnect();};
  },[]);

  return <style>{`
    .correction-week-board .correction-student.moved,
    .correction-week-board .correction-student.extra{display:none!important}
    .correction-week-board .correction-student.ghost{display:flex!important;opacity:1!important;border:0!important;background:#faf7f8!important}
    .correction-week-board .correction-student.ghost>em{display:none!important}
    .correction-change-badge{display:inline-flex;align-items:center;margin-left:5px;padding:1px 6px;border-radius:999px;font-size:9px;font-style:normal;font-weight:800;line-height:1.5;vertical-align:middle;white-space:nowrap}
    .correction-change-badge.move{background:#fff0df;color:#b76518;border:1px solid #f2c891}
    .correction-change-badge.extra{background:#eaf7ef;color:#28744b;border:1px solid #b9dfc8}
    .correction-change-badge.detail{width:max-content;margin:5px 0 0;padding:3px 7px;font-size:10px}
    .correction-change-origin{display:block!important;margin-top:3px!important;color:#a26a45!important;font-size:10px!important;line-height:1.35!important}
  `}</style>;
}
