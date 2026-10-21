"use client";
import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { contactName, contactsVCard, exportContacts, type ContactMode, type ContactStudent } from "./contact-export-model";
import { defaultContactFilters, matchesContactFilters, type ContactFilters } from "./contact-export-filters";
import styles from "./contact-export.module.css";
import roster from "./student-roster-print.module.css";

export function ContactExportButton({ rows, allRows = rows, disabled = false }: { rows: ContactStudent[]; allRows?: ContactStudent[]; disabled?: boolean }) {
  const [open, setOpen] = useState(false);
  return <><button type="button" className={roster.launch} disabled={disabled || !allRows.length} onClick={() => setOpen(true)}>연락처 내보내기</button>{open && <ContactExportDialog rows={rows} allRows={allRows} onClose={() => setOpen(false)} />}</>;
}
export function ContactExportDialog({ rows, allRows = rows, onClose }: { rows: ContactStudent[]; allRows?: ContactStudent[]; onClose: () => void }) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [filters,setFilters]=useState<ContactFilters>(defaultContactFilters);
  const [scope,setScope]=useState<"current"|"all">("current");
  const [mode, setMode] = useState<ContactMode>("both");
  const [excluded, setExcluded] = useState<Set<string>>(() => new Set());
  const [downloading, setDownloading] = useState(false);
  const [message, setMessage] = useState("");
  useEffect(() => { const node = dialog.current; node?.showModal(); return () => node?.close(); }, []);
  const source=[...new Map((scope==="current"?rows:allRows).map(r=>[r.id,r])).values()];
  const candidates=source.filter(r=>matchesContactFilters(r,filters)).sort((a,b)=>contactName(a).localeCompare(contactName(b),"ko"));
  const chosen=candidates.filter(r=>!excluded.has(r.id));
  const {contacts,skipped,merged}=exportContacts(chosen,mode);
  const unique=(values:string[])=>[...new Set(values)].sort((a,b)=>a.localeCompare(b,"ko",{numeric:true}));
  const schools=unique(source.map(r=>r.school?.trim()||"학교 미등록"));
  const grades=unique(source.map(r=>r.grade?.trim()||"학년 미등록"));
  const enrollments=source.flatMap(r=>(r.enrollments??[]).filter(e=>e.status==="active"&&e.classes));
  const subjects=unique(enrollments.map(e=>e.classes!.subject));
  const classes=[...new Map(enrollments.map(e=>[e.class_id,{id:e.class_id,name:`${e.classes!.name} · ${e.classes!.subject}`}])).values()].sort((a,b)=>a.name.localeCompare(b.name,"ko"));
  function toggle(key:Exclude<keyof ContactFilters,"query">,value:string){setFilters(old=>({...old,[key]:old[key].includes(value)?old[key].filter(v=>v!==value):[...old[key],value]}));setMessage("")}
  function filterGroup(key:Exclude<keyof ContactFilters,"query">,label:string,items:{id:string;name:string}[]){return <fieldset className={styles.filterGroup}><legend>{label}<small>{filters[key].length?`${filters[key].length}개 선택`:"전체"}</small></legend><div><button type="button" disabled={downloading} aria-pressed={!filters[key].length} onClick={()=>{setFilters(old=>({...old,[key]:[]}));setMessage("")}}>전체</button>{items.map(item=><button type="button" key={item.id} disabled={downloading} aria-pressed={filters[key].includes(item.id)} onClick={()=>toggle(key,item.id)}>{item.name}</button>)}</div></fieldset>}
  async function download(format: "vcf" | "xlsx") {
    if (!contacts.length || downloading) return;
    setDownloading(true);
    setMessage("");
    try {
      const blob = format === "xlsx"
        ? new Blob([(await import("./contact-export-excel")).contactsExcel(contacts)], { type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" })
        : new Blob([contactsVCard(contacts)], { type: "text/vcard;charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a"); a.href = url; a.download = `한살매_연락처_${new Date().toLocaleDateString("sv-SE",{timeZone:"Asia/Seoul"})}.${format}`;
      document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url), 30000);
      setMessage(format === "xlsx" ? "엑셀 파일을 내려받았습니다. 전화번호는 앞자리 0이 유지되도록 저장했습니다." : "연락처 파일을 내려받았습니다. 갤럭시 연락처 앱에서 가져오세요.");
    } catch { setMessage("파일을 만들지 못했습니다. 다시 시도해 주세요."); }
    finally { setDownloading(false); }
  }
  return createPortal(<dialog ref={dialog} className={styles.dialog} aria-labelledby="contact-export-title" onCancel={e => { e.preventDefault(); onClose(); }} onClick={e => { if (e.target === e.currentTarget) onClose(); }}>
    <header><div><small>CONTACTS</small><h2 id="contact-export-title">연락처 내보내기</h2><p>학교·학년을 앞에 붙여 휴대폰에서도 쉽게 찾으세요.</p></div><button type="button" aria-label="연락처 내보내기 닫기" onClick={onClose}>×</button></header>
    <div className={styles.body}>
      <div className={styles.scopeTabs} role="group" aria-label="연락처 분류 범위"><button type="button" disabled={downloading} aria-pressed={scope==="current"} onClick={()=>{setScope("current");setMessage("")}}>현재 목록 {rows.length}명</button><button type="button" disabled={downloading} aria-pressed={scope==="all"} onClick={()=>{setScope("all");setMessage("")}}>전체 학생 {allRows.length}명</button></div>
      <section className={styles.filterPanel} aria-label="연락처 상세 분류"><div className={styles.heading}><h3>내보낼 대상 분류</h3><button type="button" disabled={downloading} onClick={()=>{setFilters(defaultContactFilters());setExcluded(new Set());setMessage("")}}>분류 초기화</button></div><p className={styles.help}>같은 항목은 여러 개 선택할 수 있어요. 학교·학년·과목·반 조건을 함께 적용합니다.</p>
      {filterGroup("schools","학교",schools.map(v=>({id:v,name:v})))}
      {filterGroup("grades","학년",grades.map(v=>({id:v,name:v})))}
      <details className={styles.extraFilters}><summary>과목·반 세부 분류{filters.subjects.length+filters.classes.length?` · ${filters.subjects.length+filters.classes.length}개 선택`:""}</summary>{filterGroup("subjects","과목",subjects.map(v=>({id:v,name:v})))}{filterGroup("classes","반",classes)}<p className={styles.help}>과목·반은 현재 수강 중인 반을 기준으로 분류합니다.</p></details>
      {filterGroup("statuses","재원 상태",[{id:"active",name:"재원"},{id:"paused",name:"휴원"},{id:"completed",name:"퇴원"}])}
      <input className={styles.search} type="search" disabled={downloading} aria-label="내보낼 학생 검색" placeholder="학생 이름·학교·학년·반 검색" value={filters.query} onChange={e=>{setFilters(old=>({...old,query:e.target.value}));setMessage("")}}/>
      </section>
      <div className={styles.options}><span>분류 결과 <b>{candidates.length}명</b> · 선택 <b>{chosen.length}명</b></span><label>번호 선택<select disabled={downloading} value={mode} onChange={e=>{setMode(e.target.value as ContactMode);setMessage("")}}><option value="both">학생 + 학부모</option><option value="student">학생만</option><option value="guardian">학부모만</option></select></label></div>
      <details className={styles.picker}><summary>학생 개별 선택·제외 <b>{chosen.length} / {candidates.length}명</b></summary><div className={styles.actions}><button type="button" disabled={downloading} onClick={()=>{setExcluded(old=>new Set([...old].filter(id=>!candidates.some(r=>r.id===id))));setMessage("")}}>분류 결과 전체 선택</button><button type="button" disabled={downloading} onClick={()=>{setExcluded(old=>new Set([...old,...candidates.map(r=>r.id)]));setMessage("")}}>분류 결과 전체 해제</button></div><div className={styles.choices}>{candidates.map(r=><label key={r.id}><input type="checkbox" disabled={downloading} checked={!excluded.has(r.id)} onChange={()=>{setExcluded(old=>{const next=new Set(old);if(next.has(r.id))next.delete(r.id);else next.add(r.id);return next});setMessage("")}}/>{contactName(r)}</label>)}{!candidates.length&&<p>조건에 맞는 학생이 없습니다. 분류 조건이나 범위를 변경해 주세요.</p>}</div></details>
      <div className={styles.heading}><h3>저장 이름 미리보기</h3><b>{contacts.length}개 연락처</b></div>
      <div className={styles.preview}>{contacts.length ? contacts.map(c => <div key={`${c.kind}:${c.phone}`}><span>{c.name}</span><small>{c.phone}</small></div>) : <p>내보낼 연락처가 없습니다. 학생 선택과 번호 등록 여부를 확인하세요.</p>}</div>
      <p className={styles.help}>번호가 없는 항목은 제외합니다. 동일한 학부모 번호는 하나로 합칩니다.{merged > 0 ? ` 중복 ${merged}건을 합쳤습니다.` : ""}{skipped > 0 ? ` 번호 형식을 확인할 수 없는 ${skipped}건은 제외했습니다.` : ""}</p>
      <div className={styles.guide}><b>갤럭시에 넣는 방법</b><p>VCF 파일을 휴대폰으로 옮긴 뒤 연락처 앱의 ‘연락처 가져오기’에서 선택하세요. 저장된 이름은 내보내는 시점의 학교·학년 기준입니다.</p><p>엑셀은 명단 확인·수정용입니다. 휴대폰 연락처로 가져올 때는 VCF를 사용하세요.</p></div>
      {message && <p className={styles.status} role="status">{message}</p>}
    </div><footer><span>선택 학생 {chosen.length}명</span><button type="button" onClick={onClose}>닫기</button><button type="button" className={styles.download} disabled={!contacts.length || downloading} onClick={() => void download("vcf")}>VCF 다운로드</button><button type="button" className={`${styles.download} ${styles.primary}`} disabled={!contacts.length || downloading} onClick={() => void download("xlsx")}>{downloading ? "파일 준비 중…" : "엑셀 다운로드"}</button></footer>
  </dialog>, document.body);
}
