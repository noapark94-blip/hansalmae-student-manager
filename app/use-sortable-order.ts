"use client";

import { useCallback, useEffect, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";

export function reorderById<T extends { id: string }>(items: T[], activeId: string, overId: string) {
  const from = items.findIndex((item) => item.id === activeId);
  const to = items.findIndex((item) => item.id === overId);
  if (from < 0 || to < 0 || from === to) return items;
  const next = [...items];
  const [moved] = next.splice(from, 1);
  next.splice(to, 0, moved);
  return next;
}

type SortableOptions = { activationDelayMs?: number; requireHoldForMouse?: boolean };
type PendingDrag = { id:string; element:HTMLElement; x:number; y:number; currentX:number; currentY:number; pointerType:string; holdToDrag:boolean; delayMs:number; isClassCard:boolean; pointerId:number };

export function useSortableOrder(onMove:(activeId:string,overId:string)=>void, options:SortableOptions={}) {
  const { activationDelayMs=420, requireHoldForMouse=false }=options;
  const [draggingId,setDraggingId]=useState("");
  const timer=useRef<ReturnType<typeof setTimeout>|null>(null);
  const active=useRef(""); const pending=useRef<PendingDrag|null>(null); const lastOver=useRef("");
  const preview=useRef<HTMLElement|null>(null); const offset=useRef({x:0,y:0}); const didLongPress=useRef(false);

  const clear=useCallback(()=>{ if(timer.current) clearTimeout(timer.current); timer.current=null; },[]);
  const removePreview=useCallback(()=>{ const n=preview.current; preview.current=null; if(n?.isConnected)n.remove(); document.querySelectorAll(".sortable-drag-preview").forEach(n=>n.remove()); },[]);
  const createPreview=useCallback((element:HTMLElement,x:number,y:number)=>{
    removePreview(); const r=element.getBoundingClientRect(); const card=element.cloneNode(true) as HTMLElement;
    card.className="sortable-drag-preview"; card.removeAttribute("data-sort-id");
    Object.assign(card.style,{position:"fixed",left:`${r.left}px`,top:`${r.top}px`,width:`${r.width}px`,height:`${r.height}px`,margin:"0",zIndex:"10000",pointerEvents:"none",opacity:".94",transform:"scale(.98)",boxShadow:"0 18px 42px rgba(55,35,45,.18)",background:"#fff",boxSizing:"border-box"});
    offset.current={x:x-r.left,y:y-r.top}; document.body.appendChild(card); preview.current=card;
  },[removePreview]);
  const startDrag=useCallback((p:PendingDrag)=>{
    active.current=p.id; lastOver.current=""; didLongPress.current=p.isClassCard; createPreview(p.element,p.currentX,p.currentY); setDraggingId(p.id);
    if(p.isClassCard && typeof navigator!=="undefined" && "vibrate" in navigator) navigator.vibrate?.(18);
  },[createPreview]);
  const move=useCallback((x:number,y:number)=>{
    if(!active.current)return; if(preview.current){preview.current.style.left=`${x-offset.current.x}px`;preview.current.style.top=`${y-offset.current.y}px`;}
    const target=document.elementFromPoint(x,y)?.closest<HTMLElement>("[data-sort-id]"); const overId=target?.dataset.sortId;
    if(overId&&overId!==active.current&&overId!==lastOver.current){onMove(active.current,overId);lastOver.current=overId;}
  },[onMove]);
  const end=useCallback(()=>{clear(); pending.current=null; active.current=""; lastOver.current=""; setDraggingId(""); removePreview(); setTimeout(()=>{didLongPress.current=false},0);},[clear,removePreview]);
  const handleMove=useCallback((e:PointerEvent)=>{
    const p=pending.current;
    if(p){ p.currentX=e.clientX; p.currentY=e.clientY; }
    if(!active.current&&p){
      const d=Math.hypot(e.clientX-p.x,e.clientY-p.y);
      if(p.pointerType==="mouse"&&!p.holdToDrag){if(d>=7)startDrag(p);}
      else if(!p.isClassCard&&d>=12){clear();pending.current=null;return;}
      /* Class cards deliberately do not cancel a long press for small movement. */
    }
    if(active.current){e.preventDefault();move(e.clientX,e.clientY);}
  },[clear,move,startDrag]);
  useEffect(()=>{
    window.addEventListener("pointermove",handleMove,{passive:false}); window.addEventListener("pointerup",end); window.addEventListener("pointercancel",end); window.addEventListener("blur",end);
    return()=>{window.removeEventListener("pointermove",handleMove);window.removeEventListener("pointerup",end);window.removeEventListener("pointercancel",end);window.removeEventListener("blur",end);end();};
  },[end,handleMove]);

  return { draggingId,
    itemProps:(id:string)=>({
      "data-sort-id":id,
      onContextMenu:(e:React.MouseEvent<HTMLElement>)=>e.preventDefault(),
      onClickCapture:(e:React.MouseEvent<HTMLElement>)=>{if(didLongPress.current){e.preventDefault();e.stopPropagation();}},
      onPointerDown:(e:ReactPointerEvent<HTMLElement>)=>{
        if((e.target as HTMLElement).closest("input,select,textarea,a"))return;
        const isClassCard=Boolean(e.currentTarget.closest(".teacher-class-cards")); const holdToDrag=isClassCard||e.pointerType!=="mouse"||requireHoldForMouse; const delayMs=isClassCard?1800:activationDelayMs;
        didLongPress.current=false;
        pending.current={id,element:e.currentTarget,x:e.clientX,y:e.clientY,currentX:e.clientX,currentY:e.clientY,pointerType:e.pointerType,holdToDrag,delayMs,isClassCard,pointerId:e.pointerId};
        clear();
        try{e.currentTarget.setPointerCapture(e.pointerId);}catch{}
        if(holdToDrag) timer.current=setTimeout(()=>{const p=pending.current;if(p&&!active.current)startDrag(p);},delayMs);
      }
    })
  };
}
