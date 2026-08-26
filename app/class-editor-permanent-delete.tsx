"use client";

import { useEffect, useMemo, useState } from "react";
import { createPortal } from "react-dom";
import { createSupabaseBrowserClient } from "./supabase";
import confirmStyles from "./message-confirm.module.css";

type ManagedClassRef = { id: string; name: string };

export function ClassEditorPermanentDelete() {
  const supabase = useMemo(() => createSupabaseBrowserClient(), []);
  const [footer, setFooter] = useState<HTMLElement | null>(null);
  const [className, setClassName] = useState("");
  const [deleting, setDeleting] = useState(false);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [deleteError, setDeleteError] = useState("");

  useEffect(() => {
    const sync = () => {
      const modals = Array.from(document.querySelectorAll<HTMLElement>(".nested-modal-backdrop .class-creator"));
      const modal = modals.find((item) => item.querySelector<HTMLElement>(".eyebrow")?.textContent?.trim() === "클래스 수정") ?? null;
      const nextFooter = modal?.querySelector<HTMLElement>(":scope > footer") ?? null;
      const nextName = modal?.querySelector<HTMLElement>(":scope > header h2")?.textContent?.trim() ?? "";
      setFooter((current) => (current === nextFooter ? current : nextFooter));
      setClassName((current) => (current === nextName ? current : nextName));
    };

    sync();
    const observer = new MutationObserver(sync);
    observer.observe(document.body, { childList: true, subtree: true });
    return () => observer.disconnect();
  }, []);

  if (!footer || !className) return null;

  const remove = async () => {
    if (!supabase || deleting) return;
    setDeleting(true);
    setDeleteError("");
    const { data, error: loadError } = await supabase.rpc("staff_manage_classes");
    if (loadError) {
      setDeleteError(`클래스 정보를 확인하지 못했습니다. ${loadError.message}`);
      setDeleting(false);
      return;
    }
    const target = ((data ?? []) as ManagedClassRef[]).find((item) => item.name === className);
    if (!target) {
      setDeleteError("삭제할 클래스를 찾지 못했습니다. 창을 닫고 다시 시도해 주세요.");
      setDeleting(false);
      return;
    }

    const { error: deleteError } = await supabase.rpc("admin_permanently_delete_class", { p_class_id: target.id });
    if (deleteError) {
      setDeleteError(deleteError.message);
      setDeleting(false);
      return;
    }
    window.location.reload();
  };

  return <>{createPortal(
    <button
      type="button"
      className="danger-button class-editor-permanent-delete"
      disabled={deleting}
      onClick={() => { setDeleteError(""); setConfirmOpen(true); }}
      style={{ order: -1, marginRight: "auto" }}
    >
      {deleting ? "삭제 중…" : "영구 삭제"}
    </button>,
    footer,
  )}{confirmOpen ? createPortal(<div className={confirmStyles.backdrop} onMouseDown={(event) => { if (event.target === event.currentTarget && !deleting) setConfirmOpen(false); }}><section className={`${confirmStyles.dialog} ${confirmStyles.danger}`} role="alertdialog" aria-modal="true" aria-labelledby="class-delete-confirm-title"><button type="button" className={confirmStyles.close} aria-label="영구 삭제 확인창 닫기" disabled={deleting} onClick={() => setConfirmOpen(false)}>×</button><div className={confirmStyles.icon} aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M5 7h14M9 7V4.5h6V7m-8 0 1 13h8l1-13M10 10.5v6M14 10.5v6"/></svg></div><p className={confirmStyles.eyebrow}>클래스 영구 삭제</p><h3 id="class-delete-confirm-title">{className} 클래스를 삭제할까요?</h3><p className={confirmStyles.copy}>이 클래스에 연결된 운영 기록이 모두 함께 삭제됩니다.</p><div className={confirmStyles.stats}><span><small>학생</small><b>수강 배정</b></span><span><small>수업</small><b>시간표·출결</b></span><span><small>학습</small><b>기록·시험·과제</b></span></div><div className={confirmStyles.notice}><i aria-hidden="true">!</i><span>{deleteError || "삭제한 클래스와 기록은 되돌릴 수 없습니다."}</span></div><footer><button type="button" className={confirmStyles.cancel} disabled={deleting} onClick={() => setConfirmOpen(false)}>돌아가기</button><button type="button" className={confirmStyles.primary} disabled={deleting} onClick={() => void remove()}>{deleting ? "삭제 중…" : "영구 삭제"}</button></footer></section></div>, document.body) : null}</>;
}
