"use client";
import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { contactName, contactsVCard, exportContacts, type ContactMode, type ContactStudent } from "./contact-export-model";
import styles from "./contact-export.module.css";
import roster from "./student-roster-print.module.css";

export function ContactExportButton({ rows, disabled = false }: { rows: ContactStudent[]; disabled?: boolean }) {
  const [open, setOpen] = useState(false);
  return <><button type="button" className={roster.launch} disabled={disabled || !rows.length} onClick={() => setOpen(true)}>연락처 내보내기</button>{open && <ContactExportDialog rows={rows} onClose={() => setOpen(false)} />}</>;
}
export function ContactExportDialog({ rows, onClose }: { rows: ContactStudent[]; onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [activeOnly, setActiveOnly] = useState(true), [mode, setMode] = useState<ContactMode>("both");
  const [excluded, setExcluded] = useState<Set<string>>(() => new Set());
  const [query, setQuery] = useState(""); const [message, setMessage] = useState("");
  useEffect(() => { const node = dialog.current; node?.showModal(); return () => node?.close(); }, []);
  const candidates = [...new Map(rows.filter(r => !activeOnly || r.status === "active" || r.status === "재원").map(r => [r.id,r])).values()].sort((a,b) => contactName(a).localeCompare(contactName(b),"ko"));
  const chosen = candidates.filter(r => !excluded.has(r.id));
  const { contacts, skipped, merged } = exportContacts(chosen, mode);
  const choices = candidates.filter(r => contactName(r).toLocaleLowerCase().includes(query.trim().toLocaleLowerCase()));
  function download() {
    if (!contacts.length) return;
    try {
      const url = URL.createObjectURL(new Blob([contactsVCard(contacts)], { type: "text/vcard;charset=utf-8" }));
      const a = document.createElement("a"); a.href = url; a.download = `한살매_연락처_${new Date().toLocaleDateString("sv-SE",{timeZone:"Asia/Seoul"})}.vcf`;
      document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 30000);
      setMessage("연락처 파일을 내려받았습니다. 갤럭시 연락처 앱에서 가져오세요.");
    } catch { setMessage("파일을 만들지 못했습니다. 다시 시도해 주세요."); }
  }
  return createPortal(<dialog ref={dialog} className={styles.dialog} aria-labelledby="contact-export-title" onCancel={e => { e.preventDefault(); onClose(); }} onClick={e => { if (e.target === e.currentTarget) onClose(); }}>
    <header><div><small>CONTACTS</small><h2 id="contact-export-title">연락처 내보내기</h2><p>학교·학년을 앞에 붙여 휴대폰에서도 쉽게 찾으세요.</p></div><button type="button" aria-label="연락처 내보내기 닫기" onClick={onClose}>×</button></header>
    <div className={styles.body}>
      <p className={styles.scope}>현재 학생 목록의 검색·반 필터 결과 {rows.length}명에서 선택합니다.</p>
      <div className={styles.options}><label><input type="checkbox" checked={activeOnly} onChange={e => {setActiveOnly(e.target.checked);setMessage("");}}/>재원생만</label><label>번호 선택<select value={mode} onChange={e => {setMode(e.target.value as ContactMode);setMessage("");}}><option value="both">학생 + 학부모</option><option value="student">학생만</option><option value="guardian">학부모만</option></select></label></div>
      <details className={styles.picker}><summary>학생 선택 <b>{chosen.length} / {candidates.length}명</b></summary><input type="search" aria-label="내보낼 학생 검색" placeholder="학교·학년·이름 검색" value={query} onChange={e => setQuery(e.target.value)}/><div className={styles.actions}><button type="button" onClick={() => {setExcluded(new Set());setMessage("");}}>전체 선택</button><button type="button" onClick={() => {setExcluded(new Set(candidates.map(r=>r.id)));setMessage("");}}>전체 해제</button></div><div className={styles.choices}>{choices.map(r => <label key={r.id}><input type="checkbox" checked={!excluded.has(r.id)} onChange={() => {setExcluded(old => {const next = new Set(old);if(next.has(r.id))next.delete(r.id);else next.add(r.id);return next;});setMessage("");}}/>{contactName(r)}</label>)}</div></details>
      <div className={styles.heading}><h3>저장 이름 미리보기</h3><b>{contacts.length}개 연락처</b></div>
      <div className={styles.preview}>{contacts.length ? contacts.map(c => <div key={`${c.kind}:${c.phone}`}><span>{c.name}</span><small>{c.phone}</small></div>) : <p>내보낼 연락처가 없습니다. 학생 선택과 번호 등록 여부를 확인하세요.</p>}</div>
      <p className={styles.help}>번호가 없는 항목은 제외합니다. 동일한 학부모 번호는 하나로 합칩니다.{merged > 0 ? ` 중복 ${merged}건을 합쳤습니다.` : ""}{skipped > 0 ? ` 번호 형식을 확인할 수 없는 ${skipped}건은 제외했습니다.` : ""}</p>
      <div className={styles.guide}><b>갤럭시에 넣는 방법</b><p>VCF 파일을 휴대폰으로 옮긴 뒤 연락처 앱의 ‘연락처 가져오기’에서 선택하세요. 저장된 이름은 내보내는 시점의 학교·학년 기준입니다.</p></div>
      {message && <p className={styles.status} role="status">{message}</p>}
    </div><footer><span>선택 학생 {chosen.length}명</span><button type="button" onClick={onClose}>닫기</button><button type="button" className={styles.primary} disabled={!contacts.length} onClick={download}>연락처 파일 받기 (.vcf)</button></footer>
  </dialog>, document.body);
}
