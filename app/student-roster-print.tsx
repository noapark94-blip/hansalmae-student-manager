"use client";

import { useEffect, useId, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import type { StudentRow } from "./supabase";
import { defaultRosterOptions, printStudentRoster, rosterCell, rosterColumns, rosterGroups, ROSTER_FIELDS, ROSTER_PAPER_CSS, type RosterPrintOptions, type RosterScope, type RosterSort } from "./student-roster-print-model";
import styles from "./student-roster-print.module.css";

function PrintIcon() { return <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true"><path d="M7 8V3h10v5M7 17H4V9h16v8h-3"/><path d="M7 14h10v7H7zM17 11h.01"/></svg>; }

export function StudentRosterPrintButton({ rows, scope, disabled }: { rows: StudentRow[]; scope: RosterScope; disabled: boolean }) {
  const [open, setOpen] = useState(false);
  return <><button type="button" className={styles.launch} disabled={disabled || !rows.length} onClick={() => setOpen(true)} title={!rows.length ? "검색 조건에 맞는 학생이 없습니다." : "현재 검색·필터 결과로 명단 인쇄"}><PrintIcon/>명단 인쇄</button>{open && <RosterPrintDialog rows={rows} scope={scope} onClose={() => setOpen(false)}/>}</>;
}

function RosterPrintDialog({ rows, scope, onClose }: { rows: StudentRow[]; scope: RosterScope; onClose: () => void }) {
  const [options, setOptions] = useState<RosterPrintOptions>(defaultRosterOptions);
  const [error, setError] = useState("");
  const [date] = useState(() => new Intl.DateTimeFormat("ko-KR", { timeZone: "Asia/Seoul", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date()));
  const root = useRef<HTMLElement>(null);
  const titleId = useId();
  const groups = useMemo(() => rosterGroups(rows, options.sort, scope), [rows, options.sort, scope]);
  const columns = rosterColumns(options);
  const uniqueCount = new Set(rows.map(row => row.id)).size;
  const lineCount = groups.reduce((total, g) => total + g.students.length, 0);
  const patch = (value: Partial<RosterPrintOptions>) => { setOptions(previous => ({ ...previous, ...value })); setError(""); };
  useEffect(() => {
    const previous = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    root.current?.querySelector<HTMLInputElement>('input[type="text"]')?.focus();
    const keydown = (event: KeyboardEvent) => {
      if (event.key === "Escape") { event.preventDefault(); onClose(); return; }
      if (event.key !== "Tab") return;
      const items = Array.from(root.current?.querySelectorAll<HTMLElement>('button:not(:disabled),input:not(:disabled),select:not(:disabled),[tabindex="0"]') ?? []).filter(e => e.getClientRects().length);
      const first = items[0], last = items[items.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
    };
    document.addEventListener("keydown", keydown);
    return () => { document.removeEventListener("keydown", keydown); document.body.style.overflow = overflow; previous?.focus(); };
  }, [onClose]);
  const print = () => { try { printStudentRoster(rows, options, scope, date); setError(""); } catch (e) { setError(e instanceof Error ? e.message : "인쇄 창을 열지 못했습니다. 다시 시도해 주세요."); } };
  return createPortal(<div className={styles.backdrop} onMouseDown={e => { if (e.target === e.currentTarget) onClose(); }}><section ref={root} className={styles.dialog} role="dialog" aria-modal="true" aria-labelledby={titleId}>
    <header className={styles.header}><div><small>STUDENT ROSTER</small><h2 id={titleId}>학생명단 인쇄</h2><p>필요한 항목만 골라, 한 장씩 깔끔하게.</p></div><button type="button" className={styles.close} onClick={onClose} aria-label="명단 인쇄 닫기">×</button></header>
    <div className={styles.layout}><aside className={styles.settings} aria-label="인쇄 설정">
      <section className={styles.scope}><small>인쇄 대상</small><strong>{uniqueCount}명</strong><p>{scope.summary}</p><span>현재 학생 화면의 검색·필터 결과입니다.</span></section>
      <label className={styles.field}><span>명단 제목</span><input type="text" maxLength={100} value={options.title} onChange={e => patch({ title: e.target.value })} placeholder="예: 중등부 학생명단"/></label>
      <label className={styles.field}><span>정렬 방식</span><select value={options.sort} onChange={e => patch({ sort: e.target.value as RosterSort })}><option value="name">가나다순</option><option value="class">반별로 묶기</option><option value="school">학교순</option><option value="grade">학년순</option><option value="current">학생 화면 순서 그대로</option></select></label>
      {options.sort === "class" && <p className={styles.note}>여러 반을 듣는 학생은 각 반에 표시됩니다. {uniqueCount}명 · 명단 {lineCount}행</p>}
      <fieldset className={styles.fields}><legend>인쇄 항목</legend><p>학생명과 번호는 항상 포함됩니다.</p><div>{ROSTER_FIELDS.map(field => <label key={field.id}><input type="checkbox" checked={options.fields.includes(field.id)} onChange={e => patch({ fields: e.target.checked ? [...options.fields, field.id] : options.fields.filter(id => id !== field.id) })}/><span>{field.label}</span></label>)}</div></fieldset>
      <fieldset className={styles.orientation}><legend>용지 방향</legend><div>{([ ["portrait", "A4 세로"], ["landscape", "A4 가로"] ] as const).map(([id, label]) => <label key={id} className={options.orientation === id ? styles.selected : ""}><input type="radio" name={titleId + "orientation"} checked={options.orientation === id} onChange={() => patch({ orientation: id })}/>{label}</label>)}</div></fieldset>
      <p className={styles.note}>항목이 많으면 가로 방향을 선택하세요. PDF는 인쇄 창에서 ‘PDF로 저장’을 선택하면 됩니다.</p>
    </aside><div className={styles.previewPanel}><div className={styles.previewHeading}><b>인쇄 미리보기</b><span>A4 · {options.orientation === "portrait" ? "세로" : "가로"} · {uniqueCount}명</span></div><div className={styles.previewScroll} tabIndex={0} role="region" aria-label="전체 학생명단 미리보기"><style>{ROSTER_PAPER_CSS}</style><main className={`roster-paper${options.orientation === "landscape" ? " is-landscape" : ""}`}><header className="roster-heading"><div className="roster-brand">한살매 입시전문학원 · STUDENT ROSTER</div><h1>{options.title || "학생명단"}</h1><div className="roster-meta"><span>{scope.summary}</span><span>총 {uniqueCount}명 · {date}</span></div></header>{groups.map(group => <section className="roster-group" key={group.id}>{group.title && <h2>{group.title}<small>{group.students.length}명</small></h2>}<table><thead><tr><th scope="col" className="roster-number">번호</th><th scope="col" className="roster-name">학생명</th>{columns.map(field => <th scope="col" className={`field-${field.id}`} key={field.id}>{field.label}</th>)}</tr></thead><tbody>{group.students.map((student, i) => <tr key={student.id}><td className="roster-number">{i + 1}</td><td className="roster-name">{student.name}</td>{columns.map(field => <td className={`field-${field.id}`} key={field.id}>{field.id === "check" ? <span className="roster-check"/> : rosterCell(student, field.id)}</td>)}</tr>)}</tbody></table></section>)}{!groups.length && <p className="roster-empty">인쇄할 학생이 없습니다.</p>}<p className="roster-footnote">{options.sort === "class" ? "여러 반을 수강하는 학생은 각 반의 명단에 표시됩니다. · " : ""}한살매 · 학생 관리용 명단</p></main></div><p className={styles.previewNote}>전체 명단을 표시합니다. 페이지 나눔과 반복 표 머리글은 프린터 인쇄 미리보기에서 확인할 수 있습니다.</p></div></div>
    {error && <p role="alert" className={styles.error}>{error}</p>}<footer className={styles.footer}><span>{uniqueCount}명 · {columns.length + 2}개 항목</span><button type="button" onClick={onClose}>닫기</button><button type="button" className={styles.primary} disabled={!uniqueCount} onClick={print}><PrintIcon/>인쇄 · PDF 저장</button></footer>
  </section></div>, document.body);
}
