"use client";
import { useEffect, useId, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { printTimetable, timetableBodyHtml, timetableDefaults, timetableIssue, timetableRows, TIMETABLE_NOTE, TIMETABLE_PRINT_CSS, type PrintableSchedule, type TimetablePrintOptions } from "./timetable-print-model";
import styles from "./student-roster-print.module.css";
import timetableStyles from "./timetable-print.module.css";

export function TimetablePrintButton({ rows, title, subtitle = "주간 등록 시간표", disabled = false }: { rows: PrintableSchedule[]; title: string; subtitle?: string; disabled?: boolean }) {
  const [open, setOpen] = useState(false);
  return <><button type="button" className={`${styles.launch} ${timetableStyles.launch}`} disabled={disabled || !rows.length} onClick={() => setOpen(true)}><svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" aria-hidden="true"><path d="M7 8V3h10v5M7 17H4V9h16v8h-3M7 14h10v7H7z"/></svg>시간표 인쇄</button>{open && <TimetablePrintDialog rows={rows} title={title} subtitle={subtitle} onClose={() => setOpen(false)}/>}</>;
}
function TimetablePrintDialog({ rows, title, subtitle, onClose }: { rows: PrintableSchedule[]; title: string; subtitle: string; onClose: () => void }) {
  const [options, setOptions] = useState<TimetablePrintOptions>(() => timetableDefaults(title));
  const [error, setError] = useState("");
  const [date] = useState(() => new Intl.DateTimeFormat("ko-KR", { timeZone: "Asia/Seoul", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date()));
  const root = useRef<HTMLElement>(null), titleId = useId();
  const classes = useMemo(() => Array.from(new Map(rows.filter(r => r.classId).map(r => [r.classId!, { id: r.classId!, name: r.className }])).values()).sort((a, b) => a.name.localeCompare(b.name, "ko")), [rows]);
  const selected = timetableRows(rows, options), issue = timetableIssue(selected);
  const html = useMemo(() => timetableBodyHtml(rows, options, subtitle, date), [rows, options, subtitle, date]);
  const patch = (values: Partial<TimetablePrintOptions>) => { setOptions(o => ({ ...o, ...values })); setError(""); };
  useEffect(() => {
    const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null, overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden"; root.current?.querySelector<HTMLInputElement>('input[type="text"]')?.focus();
    const keydown = (e: KeyboardEvent) => {
      if (e.key === "Escape") { e.preventDefault(); e.stopImmediatePropagation(); onClose(); return; }
      if (e.key !== "Tab") return;
      const items = Array.from(root.current?.querySelectorAll<HTMLElement>('button:not(:disabled),input:not(:disabled),select:not(:disabled),[tabindex="0"]') ?? []).filter(el => el.getClientRects().length);
      if (e.shiftKey && document.activeElement === items[0]) { e.preventDefault(); items.at(-1)?.focus(); }
      else if (!e.shiftKey && document.activeElement === items.at(-1)) { e.preventDefault(); items[0]?.focus(); }
    };
    document.addEventListener("keydown", keydown, true);
    return () => { document.removeEventListener("keydown", keydown, true); document.body.style.overflow = overflow; previous?.focus(); };
  }, [onClose]);
  const print = () => { try { printTimetable(rows, options, subtitle, date); setError(""); } catch (e) { setError(e instanceof Error ? e.message : "인쇄 창을 열지 못했습니다."); } };
  return createPortal(<div className={`${styles.backdrop} ${timetableStyles.backdrop}`} onMouseDown={e => { if (e.target === e.currentTarget) onClose(); }}><section ref={root} className={styles.dialog} role="dialog" aria-modal="true" aria-labelledby={titleId}>
    <header className={styles.header}><div><small>WEEKLY TIMETABLE</small><h2 id={titleId}>시간표 인쇄</h2><p>요일과 시간을 한눈에, A4 가로로 깔끔하게.</p></div><button type="button" className={styles.close} aria-label="시간표 인쇄 닫기" onClick={onClose}>×</button></header>
    <div className={styles.layout}><aside className={styles.settings} aria-label="시간표 인쇄 설정"><section className={styles.scope}><small>인쇄 대상</small><strong>{selected.length}개 수업</strong><p>{subtitle}</p><span>A4 가로 · 전체 주간 시간표</span></section>
      <label className={styles.field}><span>시간표 제목</span><input type="text" maxLength={100} value={options.title} onChange={e => patch({ title: e.target.value })}/></label>
      {classes.length > 1 && <label className={styles.field}><span>반 선택</span><select value={options.classId} onChange={e => { const id = e.target.value; patch({ classId: id, title: id ? `${classes.find(c => c.id === id)?.name} 시간표` : title }); }}><option value="">현재 조회 범위 전체</option>{classes.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}</select></label>}
      <fieldset className={styles.fields}><legend>표시 항목</legend><div>{([["teachers", "담당 선생님"], ["rooms", "강의실"], ["activeDaysOnly", "수업 있는 요일만"]] as const).map(([id, label]) => <label key={id}><input type="checkbox" checked={options[id]} onChange={e => patch({ [id]: e.target.checked })}/><span>{label}</span></label>)}</div></fieldset>
      <p className={styles.note}>{TIMETABLE_NOTE}</p><p className={styles.note}>겹치는 수업도 모두 표시합니다. 내용이 많으면 표 머리글을 반복하며 다음 페이지로 이어집니다.</p>
    </aside><div className={styles.previewPanel}><div className={styles.previewHeading}><b>주간 시간표 미리보기</b><span>A4 가로 · {selected.length}개 수업</span></div><div className={`${styles.previewScroll} ${timetableStyles.preview}`} tabIndex={0} role="region" aria-label="전체 주간 시간표 미리보기"><style>{TIMETABLE_PRINT_CSS}</style><div dangerouslySetInnerHTML={{ __html: html }}/></div><p className={styles.previewNote}>전체 수업을 표시합니다. 페이지 나눔은 프린터 미리보기에서 확인하세요.</p></div></div>
    {(error || issue) && <p className={styles.error} role="alert">{error || issue}</p>}<footer className={styles.footer}><span>주간 {selected.length}개 수업 · A4 가로</span><button type="button" onClick={onClose}>닫기</button><button type="button" className={styles.primary} disabled={!selected.length || Boolean(issue)} onClick={print}>인쇄 · PDF 저장</button></footer>
  </section></div>, document.body);
}
