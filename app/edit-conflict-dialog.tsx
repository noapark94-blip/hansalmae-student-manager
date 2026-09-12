"use client";

import { useEffect, useRef, useState } from "react";
import styles from "./edit-conflict-dialog.module.css";

export type EditConflict = { id: string; student: string; field: string; mine: string; latest: string };
type Choices = Record<string, "mine" | "latest">;
type Request = { items: EditConflict[]; resolve: (choices: Choices | null) => void };
const eventName = "hansalmae:edit-conflicts";
export function compareEdits(items: EditConflict[]) {
  return new Promise<Choices | null>((resolve) => {
    window.dispatchEvent(new CustomEvent<Request>(eventName, { detail: { items, resolve } }));
  });
}
export function EditConflictDialogHost() {
  const [request, setRequest] = useState<Request | null>(null);
  const active = useRef<Request | null>(null);
  useEffect(() => {
    const open = (event: Event) => {
      active.current?.resolve(null);
      active.current = (event as CustomEvent<Request>).detail;
      setRequest(active.current);
    };
    window.addEventListener(eventName, open);
    return () => window.removeEventListener(eventName, open);
  }, []);
  return request ? <ConflictDialog request={request} onClose={() => { active.current = null; setRequest(null); }} /> : null;
}
function ConflictDialog({ request, onClose }: { request: Request; onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [choices, setChoices] = useState<Choices>({});
  const finish = (result: Choices | null) => {
    request.resolve(result);
    dialog.current?.close();
    onClose();
  };
  useEffect(() => {
    const previous = document.activeElement as HTMLElement | null;
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    dialog.current?.showModal();
    return () => {
      document.body.style.overflow = overflow;
      previous?.focus();
    };
  }, [request]);
  const ready = request.items.every((item) => choices[item.id]);
  return <dialog ref={dialog} className={styles.dialog} aria-labelledby="edit-conflict-title" aria-describedby="edit-conflict-description" onCancel={(event) => { event.preventDefault(); finish(null); }}>
    <header className={styles.header}>
      <div><span className={styles.eyebrow}>동시 수정 확인</span><h2 id="edit-conflict-title">저장할 내용을 선택해 주세요</h2><p id="edit-conflict-description">다른 선생님이 같은 항목을 수정했어요.<br />겹친 항목만 비교하며, 작성한 내용은 보관됩니다.</p></div>
      <button type="button" className={styles.close} aria-label="비교창 닫기" onClick={() => finish(null)}>×</button>
    </header>
    <div className={styles.body}>
      <div className={styles.count}>확인이 필요한 항목 <b>{request.items.length}개</b></div>
      {request.items.map((item, index) => <fieldset className={styles.item} key={item.id}>
        <legend><strong>{item.student}</strong><span>{item.field}</span></legend>
        <div className={styles.options}>{(["mine", "latest"] as const).map((choice) => <label key={choice} className={`${styles.option} ${choices[item.id] === choice ? styles.selected : ""}`}>
          <span className={styles.optionTitle}><input type="radio" name={`conflict-${index}`} checked={choices[item.id] === choice} onChange={() => setChoices((current) => ({ ...current, [item.id]: choice }))} /><b>{choice === "mine" ? "내 입력" : "최근 저장된 내용"}</b></span>
          <span className={styles.value}>{(choice === "mine" ? item.mine : item.latest) || "입력 없음"}</span>
        </label>)}</div>
      </fieldset>)}
    </div>
    <footer className={styles.footer}><p>선택 후에도 바로 저장되지 않습니다.<br />내용을 확인하고 저장해 주세요.</p><div><button type="button" className={styles.cancel} onClick={() => finish(null)}>돌아가기</button><button type="button" className={styles.apply} disabled={!ready} onClick={() => finish(choices)}>선택한 내용 적용</button></div></footer>
  </dialog>;
}
