"use client";

import { useCallback, useEffect, useState } from "react";
import styles from "./message-confirm.module.css";

type DialogStat = { label: string; value: string };
type DialogTone = "default" | "danger";
type DialogOptions = {
  eyebrow: string;
  title: string;
  copy?: string;
  notice?: string;
  confirmLabel?: string;
  cancelLabel?: string;
  tone?: DialogTone;
  stats?: DialogStat[];
};
type PromptOptions = DialogOptions & {
  inputLabel: string;
  initialValue?: string;
  placeholder?: string;
  inputMode?: "text" | "numeric";
};
type DialogRequest = { id: number; kind: "confirm"; options: DialogOptions } | { id: number; kind: "prompt"; options: PromptOptions };
type DialogResult = boolean | string | null;

const EVENT_NAME = "hansalmae:app-dialog";
const resolvers = new Map<number, (value: DialogResult) => void>();
let nextId = 0;

function requestDialog<T extends DialogResult>(request: Omit<DialogRequest, "id">) {
  return new Promise<T>((resolve) => {
    const id = ++nextId;
    resolvers.set(id, resolve as (value: DialogResult) => void);
    window.dispatchEvent(new CustomEvent<DialogRequest>(EVENT_NAME, { detail: { ...request, id } as DialogRequest }));
  });
}

export function appConfirm(options: DialogOptions) {
  return requestDialog<boolean>({ kind: "confirm", options });
}

export function appPrompt(options: PromptOptions) {
  return requestDialog<string | null>({ kind: "prompt", options });
}

export function AppDialogHost() {
  const [request, setRequest] = useState<DialogRequest | null>(null);
  const [value, setValue] = useState("");

  const finish = useCallback((result: DialogResult) => {
    if (!request) return;
    resolvers.get(request.id)?.(result);
    resolvers.delete(request.id);
    setRequest(null);
  }, [request]);

  useEffect(() => {
    const open = (event: Event) => {
      const next = (event as CustomEvent<DialogRequest>).detail;
      setRequest(next);
      setValue(next.kind === "prompt" ? next.options.initialValue ?? "" : "");
    };
    window.addEventListener(EVENT_NAME, open);
    return () => window.removeEventListener(EVENT_NAME, open);
  }, []);

  useEffect(() => {
    if (!request) return;
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key === "Escape") finish(request.kind === "confirm" ? false : null);
    };
    document.addEventListener("keydown", closeOnEscape);
    return () => document.removeEventListener("keydown", closeOnEscape);
  }, [finish, request]);

  if (!request) return null;
  const { options } = request;
  const danger = options.tone === "danger";
  const canSubmit = request.kind === "confirm" || Boolean(value.trim());
  const submit = () => finish(request.kind === "confirm" ? true : value.trim());

  return <div className={styles.backdrop} onMouseDown={(event) => { if (event.target === event.currentTarget) finish(request.kind === "confirm" ? false : null); }}><section className={`${styles.dialog} ${danger ? styles.danger : ""}`} role="alertdialog" aria-modal="true" aria-labelledby="app-dialog-title"><button type="button" className={styles.close} aria-label="확인창 닫기" onClick={() => finish(request.kind === "confirm" ? false : null)}>×</button><div className={styles.icon} aria-hidden="true">{danger ? <svg viewBox="0 0 24 24"><path d="M5 7h14M9 7V4.5h6V7m-8 0 1 13h8l1-13M10 10.5v6M14 10.5v6"/></svg> : <svg viewBox="0 0 24 24"><path d="M12 3.5a8.5 8.5 0 1 0 0 17 8.5 8.5 0 0 0 0-17Z"/><path d="M12 10v6M12 7.2v.2"/></svg>}</div><p className={styles.eyebrow}>{options.eyebrow}</p><h3 id="app-dialog-title">{options.title}</h3>{options.copy ? <p className={styles.copy}>{options.copy}</p> : null}{options.stats?.length ? <div className={styles.stats}>{options.stats.map((stat) => <span key={stat.label}><small>{stat.label}</small><b>{stat.value}</b></span>)}</div> : null}{request.kind === "prompt" ? <label className={styles.promptField}><span>{request.options.inputLabel}</span><input autoFocus inputMode={request.options.inputMode ?? "text"} value={value} placeholder={request.options.placeholder} onChange={(event) => setValue(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter" && canSubmit) submit(); }} /></label> : null}{options.notice ? <div className={styles.notice}><i aria-hidden="true">{danger ? "!" : "i"}</i><span>{options.notice}</span></div> : null}<footer><button type="button" className={styles.cancel} onClick={() => finish(request.kind === "confirm" ? false : null)}>{options.cancelLabel ?? "취소"}</button><button type="button" className={styles.primary} disabled={!canSubmit} onClick={submit}>{options.confirmLabel ?? "확인"}</button></footer></section></div>;
}
