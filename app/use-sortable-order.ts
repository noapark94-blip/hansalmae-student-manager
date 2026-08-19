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
  /** Delay before drag mode starts. Touch keeps the legacy 420ms default; mouse starts on movement unless requireHoldForMouse is true. */
  activationDelayMs?: number;
  /** When true, mouse must also stay pressed for activationDelayMs before dragging can begin. */
  requireHoldForMouse?: boolean;
};

export function useSortableOrder(onMove: (activeId: string, overId: string) => void, options: SortableOptions = {}) {
  const { activationDelayMs = 420, requireHoldForMouse = false } = options;
  const [draggingId, setDraggingId] = useState("");
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const active = useRef("");
  const pending = useRef<{ id: string; element: HTMLElement; x: number; y: number; pointerType: string } | null>(null);
  const lastOver = useRef("");
  const preview = useRef<HTMLElement | null>(null);
  const source = useRef<HTMLElement | null>(null);
  const offset = useRef({ x: 0, y: 0 });

  const removePreview = useCallback(() => {
    const node = preview.current;
    preview.current = null;
    source.current = null;
    if (node?.isConnected) node.remove();
    document.querySelectorAll(".sortable-drag-preview").forEach((item) => item.remove());
  }, []);

  const createPreview = useCallback((element: HTMLElement, clientX: number, clientY: number) => {
    removePreview();
    const rect = element.getBoundingClientRect();
    const style = getComputedStyle(element);
    const accent = style.getPropertyValue("--class-color").trim() || "#922d61";
    const subject = element.querySelector("small")?.textContent?.trim() || "";
    const title = element.querySelector("b,h3,h4")?.textContent?.trim() || element.innerText.trim().split("\n").filter(Boolean)[0] || "이동 중";
    const count = element.querySelector("strong")?.textContent?.trim() || "";
    const detail = element.querySelector("em")?.textContent?.trim() || "";

    const card = document.createElement("div");
    card.className = "sortable-drag-preview";
    card.innerHTML = `<i></i><div><span>${escapeHtml(subject)}</span><b>${escapeHtml(title)}</b>${detail ? `<small>${escapeHtml(detail)}</small>` : ""}</div>${count ? `<strong>${escapeHtml(count)}</strong>` : ""}`;
    Object.assign(card.style, {
      position: "fixed",
      left: `${rect.left}px`,
      top: `${rect.top}px`,
      width: `${Math.min(Math.max(rect.width * .78, 220), 300)}px`,
      minHeight: "88px",
      height: "auto",
      margin: "0",
      padding: "13px 14px",
      zIndex: "10000",
      pointerEvents: "none",
      display: "grid",
      gridTemplateColumns: "4px minmax(0,1fr) auto",
      gap: "11px",
      alignItems: "stretch",
      border: "1px solid rgba(146,45,97,.20)",
      borderRadius: "16px",
      background: "rgba(255,255,255,.97)",
      boxShadow: "0 16px 38px rgba(55,35,45,.16)",
      color: "#2d2629",
      overflow: "hidden",
      opacity: ".96",
      transform: "scale(.98)",
      backdropFilter: "blur(10px)",
      boxSizing: "border-box",
    });
    const bar = card.querySelector("i") as HTMLElement | null;
    if (bar) Object.assign(bar.style, { width: "4px", height: "100%", minHeight: "60px", borderRadius: "999px", background: accent, opacity: ".82" });
    const body = card.querySelector("div") as HTMLElement | null;
    if (body) Object.assign(body.style, { display: "flex", flexDirection: "column", minWidth: "0", gap: "4px" });
    const badge = card.querySelector("span") as HTMLElement | null;
    if (badge) Object.assign(badge.style, { width: "max-content", maxWidth: "100%", padding: "3px 7px", borderRadius: "999px", background: "#f8f1f5", color: "#922d61", fontSize: "10px", fontWeight: "800", lineHeight: "1.1", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" });
    const titleNode = card.querySelector("b") as HTMLElement | null;
    if (titleNode) Object.assign(titleNode.style, { fontSize: "15px", fontWeight: "900", lineHeight: "1.25", letterSpacing: "-.3px", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" });
    const detailNode = card.querySelector("small") as HTMLElement | null;
    if (detailNode) Object.assign(detailNode.style, { marginTop: "auto", paddingTop: "4px", color: "#857980", fontSize: "10.5px", lineHeight: "1.35", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" });
    const countNode = card.querySelector("strong") as HTMLElement | null;
    if (countNode) Object.assign(countNode.style, { alignSelf: "start", padding: "5px 7px", borderRadius: "9px", background: "#faf7f8", color: "#655a60", fontSize: "10.5px", fontWeight: "800", whiteSpace: "nowrap" });

    offset.current = {
      x: Math.min(clientX - rect.left, Number.parseFloat(card.style.width) * .7),
      y: Math.min(clientY - rect.top, 70),
    };
    source.current = element;
    document.body.appendChild(card);
    preview.current = card;
  }, [removePreview]);

  const clear = useCallback(() => {
    if (timer.current) clearTimeout(timer.current);
    timer.current = null;
  }, []);

  const startDrag = useCallback((id: string, element: HTMLElement, clientX: number, clientY: number) => {
    active.current = id;
    lastOver.current = "";
    createPreview(element, clientX, clientY);
    setDraggingId(id);
  }, [createPreview]);

  const move = useCallback((clientX: number, clientY: number) => {
    if (!active.current) return;
    if (preview.current) {
      preview.current.style.left = `${clientX - offset.current.x}px`;
      preview.current.style.top = `${clientY - offset.current.y}px`;
    }
    const target = document.elementFromPoint(clientX, clientY)?.closest<HTMLElement>("[data-sort-id]");
    const overId = target?.dataset.sortId;
    if (overId && overId !== active.current && overId !== lastOver.current) {
      onMove(active.current, overId);
      lastOver.current = overId;
    }
  }, [onMove]);

  const end = useCallback(() => {
    clear();
    pending.current = null;
    active.current = "";
    lastOver.current = "";
    setDraggingId("");
    removePreview();
  }, [clear, removePreview]);

  const handleWindowMove = useCallback((event: PointerEvent) => {
    const p = pending.current;
    if (!active.current && p) {
      const distance = Math.hypot(event.clientX - p.x, event.clientY - p.y);
      if (p.pointerType === "mouse" && !requireHoldForMouse) {
        if (distance >= 7) startDrag(p.id, p.element, event.clientX, event.clientY);
      } else if (distance >= 12) {
        // A press-and-hold should stay mostly still until reorder mode activates.
        clear();
        pending.current = null;
        return;
      }
    }
    if (active.current) {
      event.preventDefault();
      move(event.clientX, event.clientY);
    }
  }, [clear, move, requireHoldForMouse, startDrag]);

  useEffect(() => {
    window.addEventListener("pointermove", handleWindowMove, { passive: false });
    window.addEventListener("pointerup", end);
    window.addEventListener("pointercancel", end);
    window.addEventListener("blur", end);
    return () => {
      window.removeEventListener("pointermove", handleWindowMove);
      window.removeEventListener("pointerup", end);
      window.removeEventListener("pointercancel", end);
      window.removeEventListener("blur", end);
      end();
    };
  }, [end, handleWindowMove]);

  return {
    draggingId,
    itemProps: (id: string) => ({
      "data-sort-id": id,
      onPointerDown: (event: ReactPointerEvent<HTMLElement>) => {
        if ((event.target as HTMLElement).closest("button,input,select,textarea,a") && !(event.target as HTMLElement).closest("[data-drag-handle]")) return;
        pending.current = {
          id,
          element: event.currentTarget,
          x: event.clientX,
          y: event.clientY,
          pointerType: event.pointerType,
        };
        clear();
        const shouldDelay = event.pointerType !== "mouse" || requireHoldForMouse;
        if (shouldDelay) {
          timer.current = setTimeout(() => {
            const p = pending.current;
            if (p && !active.current) startDrag(p.id, p.element, p.x, p.y);
          }, activationDelayMs);
        }
      },
    }),
  };
}

function escapeHtml(value: string) {
  return value.replace(/[&<>'\"]/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '\"': "&quot;" }[char] ?? char));
}
