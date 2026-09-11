"use client";

import { useEffect, useRef, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { ConsultationClassSearch } from "./consultation-class-search";
import styles from "./mobile-consultation-search.module.css";

export function MobileConsultationSearch({ supabase }: { supabase: SupabaseClient }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [open, setOpen] = useState(false);
  useEffect(() => {
    if (!open) return;
    const previous = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const media = window.matchMedia("(max-width: 760px)");
    const closeOnDesktop = () => { if (!media.matches) dialog.current?.close(); };
    media.addEventListener("change", closeOnDesktop);
    return () => {
      document.body.style.overflow = previous;
      media.removeEventListener("change", closeOnDesktop);
    };
  }, [open]);
  return <div className={styles.mobile}>
    <button type="button" className={styles.launcher} aria-haspopup="dialog" onClick={() => { setOpen(true); dialog.current?.showModal(); }}>
      <span className={styles.icon} aria-hidden="true"><svg viewBox="0 0 24 24"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/></svg></span>
      <span className={styles.label}><strong>클래스 시간표·진도 검색</strong><small>반 이름 · 학교 · 과목 · 선생님</small></span>
      <span className={styles.arrow} aria-hidden="true">›</span>
    </button>
    <dialog ref={dialog} className={styles.dialog} aria-label="클래스 시간표·진도 검색" onClose={() => setOpen(false)}>
      <div className={styles.top}><span>상담을 위한 빠른 검색</span><button type="button" autoFocus aria-label="검색창 닫기" onClick={() => dialog.current?.close()}>×</button></div>
      <div className={styles.body}>{open && <ConsultationClassSearch supabase={supabase} />}</div>
    </dialog>
  </div>;
}
