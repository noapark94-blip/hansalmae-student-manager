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

  const clear = useCallback(() => {
    if (timer.current) clearTimeout(timer.current);
    timer.current = null;
  }, []);

  const begin = useCallback((id: string, immediate = false) => {
    clear();
    const start = () => { active.current = id; lastOver.current = ""; setDraggingId(id); };
    if (immediate) start();
    else timer.current = setTimeout(start, 420);
  }, [clear]);

  const move = useCallback((clientX: number, clientY: number) => {
    if (!active.current) return;
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
  }, [clear]);

  return {
    draggingId,
    itemProps: (id: string) => ({
      "data-sort-id": id,
      onPointerDown: (event: ReactPointerEvent<HTMLElement>) => {
        if ((event.target as HTMLElement).closest("button,input,select,textarea,a") && !(event.target as HTMLElement).closest("[data-drag-handle]")) return;
        begin(id, event.pointerType === "mouse");
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
