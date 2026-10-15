"use client";
import { useEffect, useId, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { printTimetable, timetableBodyHtml, timetableDefaults, timetableIssue, timetableRows, TIMETABLE_NOTE, TIMETABLE_PRINT_CSS, type PrintableSchedule, type TimetablePrintOptions } from "./timetable-print-model";
import { fitTimetableScale, paginateTimetableElement, type TimetablePreview } from "./timetable-preview";
import styles from "./student-roster-print.module.css";
import timetableStyles from "./timetable-print.module.css";

export function TimetablePrintButton({ rows, title, subtitle = "주간 등록 시간표", disabled = false }: { rows: PrintableSchedule[]; title: string; subtitle?: string; disabled?: boolean }) {
  const [open, setOpen] = useState(false);
  return <><button type="button" className={`${styles.launch} ${timetableStyles.launch}`} disabled={disabled || !rows.length} onClick={() => setOpen(true)}><svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" aria-hidden="true"><path d="M7 8V3h10v5M7 17H4V9h16v8h-3M7 14h10v7H7z"/></svg>시간표 인쇄</button>{open && <TimetablePrintDialog rows={rows} title={title} subtitle={subtitle} onClose={() => setOpen(false)}/>}</>;
}
function TimetablePrintDialog({ rows, title, subtitle, onClose }: { rows: PrintableSchedule[]; title: string; subtitle: string; onClose: () => void }) {
  const [options, setOptions] = useState<TimetablePrintOptions>(() => timetableDefaults(title));
  const [error, setError] = useState("");
  const [zoom, setZoom] = useState<number | null>(null), [pageIndex, setPageIndex] = useState(0), [viewportWidth, setViewportWidth] = useState(0);
  const [preview, setPreview] = useState<TimetablePreview>({ source: "", pages: [], width: 1122.52, height: 793.7, overflow: false });
  const [date] = useState(() => new Intl.DateTimeFormat("ko-KR", { timeZone: "Asia/Seoul", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date()));
  const root = useRef<HTMLElement>(null), measureRoot = useRef<HTMLDivElement>(null), viewport = useRef<HTMLDivElement>(null), titleId = useId();
  const classes = useMemo(() => Array.from(new Map(rows.filter(r => r.classId).map(r => [r.classId!, { id: r.classId!, name: r.className }])).values()).sort((a, b) => a.name.localeCompare(b.name, "ko")), [rows]);
  const selected = timetableRows(rows, options), issue = timetableIssue(selected);
  const html = useMemo(() => timetableBodyHtml(rows, options, subtitle, date), [rows, options, subtitle, date]);
  const patch = (values: Partial<TimetablePrintOptions>) => { setOptions(o => ({ ...o, ...values })); setError(""); setPageIndex(0); };
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
  useEffect(() => {
    let disposed = false;
    const measure = () => {
      if (disposed) return;
      const sheet = measureRoot.current?.querySelector<HTMLElement>(".tt-sheet");
      if (sheet) setPreview(paginateTimetableElement(sheet, html));
    };
    const frame = requestAnimationFrame(measure);
    const observer = typeof ResizeObserver !== "undefined" ? new ResizeObserver(measure) : null;
    if (measureRoot.current) observer?.observe(measureRoot.current);
    void document.fonts?.ready.then(measure);
    window.addEventListener("resize", measure);
    return () => { disposed = true; cancelAnimationFrame(frame); observer?.disconnect(); window.removeEventListener("resize", measure); };
  }, [html]);
  useEffect(() => {
    const measure = () => { if (viewport.current) setViewportWidth(viewport.current.clientWidth); };
    const frame = requestAnimationFrame(measure);
    const observer = typeof ResizeObserver !== "undefined" ? new ResizeObserver(measure) : null;
    if (viewport.current) observer?.observe(viewport.current);
    window.addEventListener("resize", measure);
    return () => { cancelAnimationFrame(frame); observer?.disconnect(); window.removeEventListener("resize", measure); };
  }, []);
  const ready = preview.source === html && preview.pages.length > 0;
  const pageCount = ready ? preview.pages.length : 0, activePage = Math.max(0, Math.min(pageIndex, pageCount - 1));
  const scale = zoom ?? fitTimetableScale(viewportWidth, preview.width);
  const changeZoom = (amount: number) => setZoom(Math.max(0.1, Math.min(1.5, Math.round((scale + amount) * 100) / 100)));
  const overflowMessage = ready && preview.overflow ? "일부 수업 정보가 한 장보다 깁니다. 제목을 줄이거나 반을 선택해 주세요." : "";
  const print = () => { if (!ready) { setError("페이지를 준비하고 있습니다. 잠시 후 다시 눌러 주세요."); return; } try { printTimetable(rows, options, subtitle, date, preview.pages); setError(""); } catch (e) { setError(e instanceof Error ? e.message : "인쇄 창을 열지 못했습니다."); } };
  return createPortal(<div className={`${styles.backdrop} ${timetableStyles.backdrop}`} onMouseDown={e => { if (e.target === e.currentTarget) onClose(); }}><section ref={root} className={`${styles.dialog} ${timetableStyles.dialog}`} role="dialog" aria-modal="true" aria-labelledby={titleId}>
    <header className={`${styles.header} ${timetableStyles.header}`}><div><small>WEEKLY TIMETABLE</small><h2 id={titleId}>시간표 인쇄</h2><p>빈칸은 줄이고, 수업과 명단은 한눈에.</p></div><button type="button" className={styles.close} aria-label="시간표 인쇄 닫기" onClick={onClose}>×</button></header>
    <div className={`${styles.layout} ${timetableStyles.layout}`}><aside className={`${styles.settings} ${timetableStyles.settings}`} aria-label="시간표 인쇄 설정"><section className={styles.scope}><small>인쇄 대상</small><strong>{selected.length}개 수업</strong><p>{subtitle}</p><span>A4 가로 · 요일별 촘촘한 배치</span></section>
      <label className={styles.field}><span>시간표 제목</span><input type="text" maxLength={100} value={options.title} onChange={e => patch({ title: e.target.value })}/></label>
      {classes.length > 1 && <label className={styles.field}><span>반 선택</span><select value={options.classId} onChange={e => { const id = e.target.value; patch({ classId: id, title: id ? `${classes.find(c => c.id === id)?.name} 시간표` : title }); }}><option value="">현재 조회 범위 전체</option>{classes.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}</select></label>}
      <fieldset className={styles.fields}><legend>표시 항목</legend><div>{([["students", "학생 이름 · 인원"], ["teachers", "담당 선생님"], ["rooms", "강의실"], ["activeDaysOnly", "수업 있는 요일만"]] as const).filter(([id]) => id !== "students" || rows.some(row => row.students !== undefined)).map(([id, label]) => <label key={id}><input type="checkbox" checked={options[id]} onChange={e => patch({ [id]: e.target.checked })}/><span>{label}</span></label>)}</div></fieldset>
      <p className={styles.note}>{TIMETABLE_NOTE}</p><p className={styles.note}>각 요일을 독립적으로 채웁니다. 명단이 길면 반 이름과 함께 다음 칸·페이지로 이어집니다.</p>
    </aside><div className={`${styles.previewPanel} ${timetableStyles.previewPanel}`}><div className={timetableStyles.previewToolbar}><b>인쇄 미리보기</b><div className={timetableStyles.zoomControls} role="group" aria-label="미리보기 배율"><button type="button" onClick={() => setZoom(null)} aria-pressed={zoom === null}>너비 맞춤</button><button type="button" aria-label="미리보기 축소" disabled={scale <= 0.1} onClick={() => changeZoom(-0.1)}>−</button><span>{Math.round(scale * 100)}%</span><button type="button" aria-label="미리보기 확대" disabled={scale >= 1.5} onClick={() => changeZoom(0.1)}>＋</button><button type="button" onClick={() => setZoom(1)} aria-pressed={zoom === 1}>100%</button></div></div>
      <div ref={viewport} className={timetableStyles.viewport} tabIndex={0} role="region" aria-label="페이지별 주간 시간표 미리보기"><style>{TIMETABLE_PRINT_CSS}</style>{ready ? <div className={timetableStyles.stage} style={{ width: preview.width * scale, height: preview.height * scale }}><div className={timetableStyles.scaledPaper} style={{ width: preview.width, height: preview.height, transform: `scale(${scale})` }} dangerouslySetInnerHTML={{ __html: preview.pages[activePage] }}/></div> : <p className={timetableStyles.pending} role="status">시간표 페이지를 준비하고 있어요…</p>}</div>
      <nav className={timetableStyles.pagination} aria-label="시간표 페이지 이동"><button type="button" disabled={!ready || activePage === 0} onClick={() => setPageIndex(activePage - 1)}>이전</button><span aria-live="polite">{ready ? `${activePage + 1} / ${pageCount}쪽` : "페이지 계산 중…"}</span><button type="button" disabled={!ready || activePage + 1 >= pageCount} onClick={() => setPageIndex(activePage + 1)}>다음</button><small>화면 배율은 인쇄 크기에 영향을 주지 않습니다.</small></nav></div></div>
    <div className={timetableStyles.measure} aria-hidden="true"><style>{TIMETABLE_PRINT_CSS}</style><div ref={measureRoot} data-timetable-measure="true" dangerouslySetInnerHTML={{ __html: html }}/></div>
    {(error || issue || overflowMessage) && <p className={styles.error} role="alert">{error || issue || overflowMessage}</p>}<footer className={styles.footer}><span>주간 {selected.length}개 수업 · {ready ? `${pageCount}쪽` : "준비 중"} · A4 가로</span><button type="button" onClick={onClose}>닫기</button><button type="button" className={styles.primary} disabled={!selected.length || Boolean(issue) || !ready || Boolean(overflowMessage)} onClick={print}>전체 인쇄 · PDF 저장</button></footer>
  </section></div>, document.body);
}
