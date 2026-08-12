"use client";

import { useCallback, useRef, useState, type PointerEvent as ReactPointerEvent } from "react";

export function reorderById<T extends { id: string }>(items: T[], activeId: string, overId: string) {
  const from = items.findIndex((item) => item.id === activeId);
  const to = items.findIndex((item) => item.id === overId);
  if (from < 0 || to < 0 || from === to) return items;
  const next = [...items];
  const [moved] = next.splice(from, 1);
  next.splice(to, 0, moved);
  return next;
}

export function useSortableOrder(onMove: (activeId: string, overId: string) => void) {
  const [draggingId, setDraggingId] = useState("");
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const active = useRef("");
  const lastOver = useRef("");
  const preview = useRef<HTMLElement | null>(null);
  const source = useRef<HTMLElement | null>(null);
  const offset = useRef({ x: 0, y: 0 });

  const removePreview = useCallback((animate = false) => {
    const node=preview.current;const target=source.current;
    preview.current=null;source.current=null;
    if(!node)return;
    if(animate&&target){const rect=target.getBoundingClientRect();node.animate([{left:node.style.left,top:node.style.top,transform:"scale(1.02)"},{left:`${rect.left}px`,top:`${rect.top}px`,transform:"scale(.98)",opacity:.35}],{duration:170,easing:"cubic-bezier(.2,.8,.2,1)"}).finished.finally(()=>node.remove());}
    else node.remove();
  }, []);

  const createPreview=useCallback((element:HTMLElement,clientX:number,clientY:number)=>{
    removePreview();const rect=element.getBoundingClientRect();const clone=element.cloneNode(true) as HTMLElement;
    offset.current={x:clientX-rect.left,y:clientY-rect.top};source.current=element;
    Object.assign(clone.style,{position:"fixed",left:`${rect.left}px`,top:`${rect.top}px`,width:`${rect.width}px`,height:`${rect.height}px`,margin:"0",zIndex:"10000",pointerEvents:"none"});
    clone.classList.add("sortable-drag-preview");document.body.appendChild(clone);preview.current=clone;
  },[removePreview]);

  const clear = useCallback(() => {
    if (timer.current) clearTimeout(timer.current);
    timer.current = null;
  }, []);

  const begin = useCallback((id: string, element:HTMLElement,clientX:number,clientY:number, immediate = false) => {
    clear();
    const start = () => { active.current = id; lastOver.current = "";createPreview(element,clientX,clientY);setDraggingId(id); };
    if (immediate) start();
    else timer.current = setTimeout(start, 420);
  }, [clear,createPreview]);

  const move = useCallback((clientX: number, clientY: number) => {
    if (!active.current) return;
    if(preview.current){preview.current.style.left=`${clientX-offset.current.x}px`;preview.current.style.top=`${clientY-offset.current.y}px`;}
    const target = document.elementFromPoint(clientX, clientY)?.closest<HTMLElement>("[data-sort-id]");
    const overId = target?.dataset.sortId;
    if (overId && overId !== active.current && overId !== lastOver.current) {
      onMove(active.current, overId);
      lastOver.current = overId;
    }
  }, [onMove]);

  const end = useCallback(() => {
    clear();
    active.current = "";
    lastOver.current = "";
    setDraggingId("");
    removePreview(true);
  }, [clear,removePreview]);

  return {
    draggingId,
    itemProps: (id: string) => ({
      "data-sort-id": id,
      onPointerDown: (event: ReactPointerEvent<HTMLElement>) => {
        if ((event.target as HTMLElement).closest("button,input,select,textarea,a") && !(event.target as HTMLElement).closest("[data-drag-handle]")) return;
        begin(id,event.currentTarget,event.clientX,event.clientY,event.pointerType === "mouse");
        event.currentTarget.setPointerCapture(event.pointerId);
      },
      onPointerMove: (event: ReactPointerEvent<HTMLElement>) => {
        if (active.current) { event.preventDefault(); move(event.clientX, event.clientY); }
      },
      onPointerUp: end,
      onPointerCancel: end,
    }),
  };
}
