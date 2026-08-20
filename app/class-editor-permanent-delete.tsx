"use client";

import { useEffect, useMemo, useState } from "react";
import { createPortal } from "react-dom";
import { createSupabaseBrowserClient } from "./supabase";

type ManagedClassRef = { id: string; name: string };

export function ClassEditorPermanentDelete() {
  const supabase = useMemo(() => createSupabaseBrowserClient(), []);
  const [footer, setFooter] = useState<HTMLElement | null>(null);
  const [className, setClassName] = useState("");
  const [deleting, setDeleting] = useState(false);

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
    const confirmed = window.confirm(
      `${className} 클래스를 영구 삭제할까요?\n\n수강 학생 배정, 시간표, 출결, 수업 기록, 시험·과제 등 이 클래스에 연결된 기록이 함께 삭제됩니다.\n이 작업은 되돌릴 수 없습니다.`,
    );
    if (!confirmed) return;

    setDeleting(true);
    const { data, error: loadError } = await supabase.rpc("staff_manage_classes");
    if (loadError) {
      window.alert(`클래스 정보를 확인하지 못했습니다.\n${loadError.message}`);
      setDeleting(false);
      return;
    }
    const target = ((data ?? []) as ManagedClassRef[]).find((item) => item.name === className);
    if (!target) {
      window.alert("삭제할 클래스를 찾지 못했습니다. 창을 닫고 다시 시도해 주세요.");
      setDeleting(false);
      return;
    }

    const { error: deleteError } = await supabase.rpc("admin_permanently_delete_class", { p_class_id: target.id });
    if (deleteError) {
      window.alert(deleteError.message);
      setDeleting(false);
      return;
    }
    window.location.reload();
  };

  return createPortal(
    <button
      type="button"
      className="danger-button class-editor-permanent-delete"
      disabled={deleting}
      onClick={() => void remove()}
      style={{ order: -1, marginRight: "auto" }}
    >
      {deleting ? "삭제 중…" : "영구 삭제"}
    </button>,
    footer,
  );
}
