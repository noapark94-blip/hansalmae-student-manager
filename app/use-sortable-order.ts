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

type SortableOptions = {
  activationDelayMs?: number;
  requireHoldForMouse?: boolean;
};

type PendingDrag = {
  id: string;
  element: HTMLElement;
  x: number;
  y: number;
  pointerType: string;
  isClassCard: boolean;
};

const REORDER_MODE_ID = "__class_reorder_mode__";

export function useSortableOrder(onMove: (activeId: string, overId: string) => void, options: SortableOptions = {}) {
  const { activationDelayMs = 420, requireHoldForMouse = false } = options;
  const [draggingId, setDraggingId] = useState("");
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const active = useRef("");
  const pending = useRef<PendingDrag | null>(null);
  const lastOver = useRef("");
  const preview = useRef<HTMLElement | null>(null);
  const offset = useRef({ x: 0, y: 0 });
  const classReorderMode = useRef(false);
  const pointerStart = useRef({ x: 0, y: 0 });

  const clearTimer = useCallback(() => {
    if (timer.current) clearTimeout(timer.current);
    timer.current = null;
  }, []);

  const removePreview = useCallback(() => {
    const node = preview.current;
    preview.current = null;
    if (node?.isConnected) node.remove();
    document.querySelectorAll(".sortable-drag-preview").forEach((item) => item.remove());
  }, []);

  const leaveClassReorderMode = useCallback(() => {
    clearTimer();
    classReorderMode.current = false;
    pending.current = null;
    active.current = "";
    lastOver.current = "";
    setDraggingId("");
    removePreview();
  }, [clearTimer, removePreview]);

  const enterClassReorderMode = useCallback((element: HTMLElement) => {
    classReorderMode.current = true;
    pending.current = null;
    active.current = "";
    lastOver.current = "";
    setDraggingId(REORDER_MODE_ID);
    if (typeof navigator !== "undefined" && "vibrate" in navigator) navigator.vibrate?.(24);
    element.blur();
  }, []);

  const createPreview = useCallback((element: HTMLElement, clientX: number, clientY: number) => {
    removePreview();
    const rect = element.getBoundingClientRect();
    const card = element.cloneNode(true) as HTMLElement;
    card.className = "sortable-drag-preview";
    card.removeAttribute("data-sort-id");
    card.removeAttribute("data-drag-handle");
    Object.assign(card.style, {
      position: "fixed",
      left: `${rect.left}px`,
      top: `${rect.top}px`,
      width: `${rect.width}px`,
      height: `${rect.height}px`,
      margin: "0",
      zIndex: "10000",
      pointerEvents: "none",
      opacity: ".96",
      transform: "scale(1.02)",
      boxShadow: "0 18px 44px rgba(55,35,45,.20)",
      background: "#fff",
      boxSizing: "border-box",
    });
    offset.current = {
      x: Math.min(Math.max(clientX - rect.left, 18), rect.width - 18),
      y: Math.min(Math.max(clientY - rect.top, 18), rect.height - 18),
    };
    document.body.appendChild(card);
    preview.current = card;
  }, [removePreview]);

  const startDrag = useCallback((id: string, element: HTMLElement, clientX: number, clientY: number) => {
    clearTimer();
    pending.current = null;
    active.current = id;
    lastOver.current = "";
    pointerStart.current = { x: clientX, y: clientY };
    createPreview(element, clientX, clientY);
    setDraggingId(id);
  }, [clearTimer, createPreview]);

  const move = useCallback((clientX: number, clientY: number) => {
    if (!active.current) return;
    if (preview.current) {
      preview.current.style.left = `${clientX - offset.current.x}px`;
      preview.current.style.top = `${clientY - offset.current.y}px`;
    }
    const cardScroller = document.querySelector<HTMLElement>(".teacher-class-cards.reorder-mode");
    if (cardScroller && cardScroller.scrollWidth > cardScroller.clientWidth) {
      const rect = cardScroller.getBoundingClientRect();
      const edge = Math.min(72, Math.max(44, rect.width * .12));
      const leftDistance = clientX - rect.left;
      const rightDistance = rect.right - clientX;
      if (leftDistance < edge) cardScroller.scrollLeft -= Math.ceil((edge - leftDistance) / 3) + 5;
      else if (rightDistance < edge) cardScroller.scrollLeft += Math.ceil((edge - rightDistance) / 3) + 5;
    }
    const target = document.elementFromPoint(clientX, clientY)?.closest<HTMLElement>("[data-sort-id]");
    const overId = target?.dataset.sortId;
    if (overId && overId !== active.current && overId !== lastOver.current) {
      onMove(active.current, overId);
      lastOver.current = overId;
    }
  }, [onMove]);

  const finishPointer = useCallback(() => {
    clearTimer();
    pending.current = null;
    lastOver.current = "";
    active.current = "";
    removePreview();
    if (classReorderMode.current) setDraggingId(REORDER_MODE_ID);
    else setDraggingId("");
  }, [clearTimer, removePreview]);

  const handleWindowMove = useCallback((event: PointerEvent) => {
    const p = pending.current;
    if (!active.current && p) {
      const distance = Math.hypot(event.clientX - p.x, event.clientY - p.y);
      if (p.isClassCard && !classReorderMode.current) {
        const cancelDistance = p.pointerType === "mouse" ? 60 : 32;
        if (distance >= cancelDistance) {
          clearTimer();
          pending.current = null;
        }
      } else if (!p.isClassCard) {
        if (p.pointerType === "mouse" && !requireHoldForMouse) {
          if (distance >= 7) startDrag(p.id, p.element, event.clientX, event.clientY);
        } else if (distance >= 12) {
          clearTimer();
          pending.current = null;
        }
      }
    }
    if (active.current) {
      event.preventDefault();
      move(event.clientX, event.clientY);
    }
  }, [clearTimer, move, requireHoldForMouse, startDrag]);

  useEffect(() => {
    const onPointerUp = () => finishPointer();
    const onPointerCancel = () => {
      if (active.current) finishPointer();
      else {
        clearTimer();
        pending.current = null;
      }
    };
    const onContextMenu = (event: MouseEvent) => {
      if ((event.target as HTMLElement | null)?.closest(".teacher-class-cards")) event.preventDefault();
    };
    const onClickCapture = (event: MouseEvent) => {
      const target = event.target as HTMLElement | null;
      if (classReorderMode.current && target?.closest(".teacher-class-cards")) {
        event.preventDefault();
        event.stopPropagation();
      }
    };
    const onOutsidePointer = (event: PointerEvent) => {
      if (!classReorderMode.current || active.current) return;
      const target = event.target as HTMLElement | null;
      if (!target?.closest(".teacher-class-cards") && !target?.closest(".sortable-drag-preview")) leaveClassReorderMode();
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape" && classReorderMode.current) leaveClassReorderMode();
    };

    window.addEventListener("pointermove", handleWindowMove, { passive: false });
    window.addEventListener("pointerup", onPointerUp);
    window.addEventListener("pointercancel", onPointerCancel);
    document.addEventListener("contextmenu", onContextMenu);
    document.addEventListener("click", onClickCapture, true);
    document.addEventListener("pointerdown", onOutsidePointer, true);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      window.removeEventListener("pointermove", handleWindowMove);
      window.removeEventListener("pointerup", onPointerUp);
      window.removeEventListener("pointercancel", onPointerCancel);
      document.removeEventListener("contextmenu", onContextMenu);
      document.removeEventListener("click", onClickCapture, true);
      document.removeEventListener("pointerdown", onOutsidePointer, true);
      document.removeEventListener("keydown", onKeyDown);
      clearTimer();
      removePreview();
    };
  }, [clearTimer, finishPointer, handleWindowMove, leaveClassReorderMode, removePreview]);

  return {
    draggingId,
    itemProps: (id: string) => ({
      "data-sort-id": id,
      onPointerDown: (event: ReactPointerEvent<HTMLElement>) => {
        const target = event.target as HTMLElement;
        if (target.closest("input,select,textarea,a")) return;
        const isClassCard = Boolean(event.currentTarget.closest(".teacher-class-cards"));

        if (isClassCard) {
          if (classReorderMode.current) {
            event.preventDefault();
            startDrag(id, event.currentTarget, event.clientX, event.clientY);
            return;
          }
          pending.current = {
            id,
            element: event.currentTarget,
            x: event.clientX,
            y: event.clientY,
            pointerType: event.pointerType,
            isClassCard: true,
          };
          clearTimer();
          timer.current = setTimeout(() => {
            const p = pending.current;
            if (p && !classReorderMode.current && !active.current) enterClassReorderMode(p.element);
          }, 1600);
          return;
        }

        pending.current = {
          id,
          element: event.currentTarget,
          x: event.clientX,
          y: event.clientY,
          pointerType: event.pointerType,
          isClassCard: false,
        };
        clearTimer();
        if (event.pointerType !== "mouse" || requireHoldForMouse) {
          timer.current = setTimeout(() => {
            const p = pending.current;
            if (p && !active.current) startDrag(p.id, p.element, p.x, p.y);
          }, activationDelayMs);
        }
      },
    }),
  };
}
