"use client";

import type { FormEvent } from "react";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Profile } from "./supabase";
import { compareEdits } from "./edit-conflict-dialog";
import { calendarValues, settingsChanges, mergeSettingsChoices } from "./settings-concurrency";
import { appConfirm } from "./app-dialog";

type Scope = "school" | "academy";
type View = "all" | Scope;
type Category = string;
type Status = "scheduled" | "completed" | "enrolled" | "cancelled" | "no_show";
type EventRow = {
  id: string; scope: Scope; school: string | null; grade: string | null; category: Category; categoryLabel: string;
  title: string; startsOn: string; endsOn: string; startsAt: string | null; endsAt: string | null;
  classId: string | null; className: string | null; teacherId: string | null; teacherName: string | null;
  note: string | null; contactName: string | null; contactPhone: string | null; location: string | null;
  status: Status; createdBy: string; authorName: string; canEdit: boolean;
};
type Named = { id: string; name: string };
type CalendarCategory = { id: string; scope: Scope; label: string; sortOrder: number; active: boolean };
type ClassOption = Named & { subject: string; teacherIds: string[] };
type Board = { events: EventRow[]; categories: CalendarCategory[]; schools: string[]; classes: ClassOption[]; teachers: Named[] };
type Holiday = { date: string; localName: string };

const defaultSchoolCategories: CalendarCategory[] = [
  { id: "exam", scope: "school", label: "중간·기말고사", sortOrder: 10, active: true },
  { id: "mock", scope: "school", label: "모의고사·수능", sortOrder: 20, active: true },
  { id: "admission", scope: "school", label: "원서접수·입시", sortOrder: 30, active: true },
  { id: "vacation", scope: "school", label: "개학·방학", sortOrder: 40, active: true },
  { id: "school", scope: "school", label: "학교 행사", sortOrder: 50, active: true },
  { id: "intensive", scope: "school", label: "시험 직전 보강", sortOrder: 60, active: true },
  { id: "other", scope: "school", label: "기타", sortOrder: 70, active: true },
];
const defaultAcademyCategories: CalendarCategory[] = [
  { id: "consultation", scope: "academy", label: "상담 예약", sortOrder: 10, active: true },
  { id: "trial", scope: "academy", label: "청강·체험", sortOrder: 20, active: true },
  { id: "placement", scope: "academy", label: "레벨테스트", sortOrder: 30, active: true },
  { id: "academy_event", scope: "academy", label: "특강·행사", sortOrder: 40, active: true },
  { id: "closure", scope: "academy", label: "휴무·운영 변경", sortOrder: 50, active: true },
  { id: "other_academy", scope: "academy", label: "기타", sortOrder: 60, active: true },
];
const statuses: { id: Status; label: string }[] = [
  { id: "scheduled", label: "예약·예정" }, { id: "completed", label: "완료" },
  { id: "enrolled", label: "등록 완료" }, { id: "cancelled", label: "취소" },
  { id: "no_show", label: "미방문" },
];
const grades = ["초6", "중1", "중2", "중3", "고1", "고2", "고3", "재수", "검정고시"];
const empty: Board = { events: [], categories: [], schools: [], classes: [], teachers: [] };

export function AcademicCalendar({ supabase, profile }: { supabase: SupabaseClient; profile: Profile }) {
  const now = new Date();
  const [month, setMonth] = useState(`${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`);
  const [data, setData] = useState<Board>(empty);
  const [holidays, setHolidays] = useState<Holiday[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [view, setView] = useState<View>("all");
  const [school, setSchool] = useState("");
  const [grade, setGrade] = useState("");
  const [category, setCategory] = useState("");
  const [mine, setMine] = useState(false);
  const [selected, setSelected] = useState(toDate(now));
  const [editing, setEditing] = useState<EventRow | "new" | null>(null);
  const [managingCategories, setManagingCategories] = useState(false);
  const [noteEvent, setNoteEvent] = useState<EventRow | null>(null);
  const year = Number(month.slice(0, 4));

  const load = useCallback(async () => {
    setLoading(true);
    const { data: result, error: loadError } = await supabase.rpc("staff_academic_calendar_board", { p_year: year });
    if (loadError) setError("일정을 불러오지 못했습니다.");
    else { setData(result as Board); setError(""); }
    setLoading(false);
  }, [supabase, year]);

  useEffect(() => { void load(); }, [load]);
  useEffect(() => {
    let active = true;
    void fetch(`https://date.nager.at/api/v3/PublicHolidays/${year}/KR`)
      .then(response => response.ok ? response.json() : Promise.reject())
      .then((rows: Holiday[]) => { if (active) setHolidays(rows); })
      .catch(() => { if (active) setHolidays(fixedHolidays(year)); });
    return () => { active = false; };
  }, [year]);

  const categories = data.categories.length ? data.categories : [...defaultSchoolCategories, ...defaultAcademyCategories];
  const categoryOptions = categories.filter(item => item.active && (view === "all" || item.scope === view));
  const categoryLabel = (id: string) => categories.find(item => item.id === id)?.label ?? data.events.find(item => item.category === id)?.categoryLabel ?? "기타";
  const filtered = useMemo(() => data.events.filter(event =>
    (view === "all" || event.scope === view) &&
    (!school || event.school === school) &&
    (!grade || event.grade === grade) &&
    (!category || event.category === category) &&
    (!mine || event.createdBy === profile.id)
  ), [data.events, view, school, grade, category, mine, profile.id]);
  const days = calendarDays(month);
  const selectedEvents = filtered.filter(event => event.startsOn <= selected && event.endsOn >= selected);
  const selectedHoliday = holidays.find(holiday => holiday.date === selected);
  const changeView = (next: View) => { setView(next); setCategory(""); setSchool(""); setGrade(""); };
  const move = (delta: number) => {
    const date = new Date(`${month}-01T00:00:00`);
    date.setMonth(date.getMonth() + delta);
    const next = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
    setMonth(next); setSelected(`${next}-01`);
  };

  return <section className="panel academic-panel">
    <header className="academic-header">
      <div><h2>학사·학원 일정</h2><p>학교 시험부터 상담·청강·레벨테스트와 학원 운영 일정까지 함께 확인합니다.</p></div>
      <div>{profile.role === "admin" && <button className="secondary-button" onClick={() => setManagingCategories(true)}>카테고리 관리</button>}<button className="primary" onClick={() => setEditing("new")}>＋ 일정 등록</button></div>
    </header>
    <nav className="academic-scope-tabs" aria-label="일정 보기">
      {([["all", "전체 일정"], ["school", "학교 일정"], ["academy", "학원 일정"]] as [View, string][]).map(([id, text]) =>
        <button key={id} className={view === id ? "active" : ""} onClick={() => changeView(id)}>{text}</button>)}
    </nav>
    <div className="academic-filters">
      <select value={school} onChange={event => setSchool(event.target.value)}><option value="">전체 학교</option>{data.schools.map(x => <option key={x}>{x}</option>)}</select>
      <select value={grade} onChange={event => setGrade(event.target.value)}><option value="">전체 학년</option>{grades.map(x => <option key={x}>{x}</option>)}</select>
      <select value={category} onChange={event => setCategory(event.target.value)}><option value="">전체 일정 종류</option>{categoryOptions.map(x => <option value={x.id} key={x.id}>{x.label}</option>)}</select>
      <label><input type="checkbox" checked={mine} onChange={event => setMine(event.target.checked)} /> 내가 작성한 일정</label>
    </div>
    {error && <p className="form-error">{error}</p>}
    <div className="academic-layout">
      <div className="academic-calendar">
        <nav><button onClick={() => move(-1)} aria-label="이전 달">‹</button><b>{year}년 {Number(month.slice(5))}월</b><button onClick={() => move(1)} aria-label="다음 달">›</button></nav>
        <div className="academic-weekdays">{["일", "월", "화", "수", "목", "금", "토"].map((x, i) => <b className={i === 0 ? "sun" : i === 6 ? "sat" : ""} key={x}>{x}</b>)}</div>
        <div className="academic-days">{days.map((day, index) => {
          if (!day) return <i key={`blank-${index}`} />;
          const date = `${month}-${String(day).padStart(2, "0")}`;
          const holiday = holidays.find(row => row.date === date);
          const events = filtered.filter(event => event.startsOn <= date && event.endsOn >= date);
          return <button key={date} className={`${selected === date ? "selected" : ""}${date === toDate(now) ? " today" : ""}`} onClick={() => setSelected(date)}>
            <strong className={holiday || index % 7 === 0 ? "holiday" : index % 7 === 6 ? "saturday" : ""}>{day}</strong>
            {holiday && <small className="holiday-name">{holiday.localName}</small>}
            <span className="academic-day-events">{events.slice(0, 3).map(event => <em className={`${event.scope} ${event.category}`} key={event.id}>{calendarEventText(event)}</em>)}{events.length > 3 && <small>+{events.length - 3}개</small>}</span>
            {events.length > 1 && <small className="academic-mobile-more">+{events.length - 1}개 · …</small>}
          </button>;
        })}</div>
      </div>
      <aside className="academic-agenda">
        <header><div><small>{selectedHoliday?.localName ?? weekdayName(selected)}</small><h3>{formatDate(selected)}</h3></div><button onClick={() => setEditing("new")} aria-label="이 날짜에 일정 추가">＋</button></header>
        {loading ? <p className="academic-empty">일정을 불러오는 중…</p> : selectedEvents.length ? <div>{selectedEvents.map(event =>
          <article key={event.id} className={`${event.scope} ${event.category}`} role="button" tabIndex={0} aria-label={`${event.title} 메모 보기`} onClick={() => setNoteEvent(event)} onKeyDown={keyEvent => { if (keyEvent.key === "Enter" || keyEvent.key === " ") { keyEvent.preventDefault(); setNoteEvent(event); } }}>
            <span>{event.scope === "academy" ? "학원 일정" : "학교 일정"} · {categoryLabel(event.category)}</span>
            <h4>{event.title}</h4>
            <div className="academic-agenda-meta">
              <div className="academic-agenda-meta-main">
                <strong>{event.scope === "academy"
                  ? (event.contactName ? [event.contactName, event.grade].filter(Boolean).join(" · ") : [event.school, event.grade].filter(Boolean).join(" · "))
                  : [event.school, event.grade].filter(Boolean).join(" · ")}</strong>
                {event.startsAt && <time>{event.startsAt.slice(0, 5)}–{event.endsAt?.slice(0, 5)}</time>}
              </div>
              {((event.scope === "academy" && event.contactName && event.school) || event.location) &&
                <div className="academic-agenda-meta-sub">
                  {[event.scope === "academy" && event.contactName ? event.school : null, event.location].filter(Boolean).join(" · ")}
                </div>}
            </div>
            <div className="academic-agenda-card-footer">
              {event.scope === "academy" && <small className={`academic-status ${event.status}`}>{statusLabel(event.status)}</small>}
              <small className="academic-byline">{event.teacherName ? `${event.teacherName} 담당 · ` : ""}{event.authorName} 작성</small>
            </div>
            {event.canEdit && <button onClick={clickEvent => { clickEvent.stopPropagation(); setEditing(event); }}>수정</button>}
          </article>)}</div> : <p className="academic-empty">등록된 일정이 없습니다.<button onClick={() => setEditing("new")}>이 날짜에 일정 추가</button></p>}
      </aside>
    </div>
    {editing && <AcademicEditor row={editing === "new" ? null : editing} initialDate={selected} initialScope={view === "school" ? "school" : "academy"} data={{...data,categories}} supabase={supabase} profile={profile} onClose={() => setEditing(null)} onSaved={async () => { setEditing(null); await load(); }} />}
    {managingCategories && <AcademicCategoryManager categories={categories} supabase={supabase} onClose={() => setManagingCategories(false)} onChanged={load} />}
    {noteEvent && <div className="modal-backdrop academic-note-backdrop" onMouseDown={mouseEvent => { if (mouseEvent.target === mouseEvent.currentTarget) setNoteEvent(null); }}>
      <section className="academic-note-modal" role="dialog" aria-modal="true" aria-labelledby="academic-note-title">
        <header><div><small>일정 메모</small><h2 id="academic-note-title">메모 내용</h2></div><button type="button" aria-label="메모 닫기" onClick={() => setNoteEvent(null)}>×</button></header>
        <div className={`academic-note-content${noteEvent.note?.trim() ? "" : " empty"}`}>{noteEvent.note?.trim() || "등록된 메모가 없습니다."}</div>
        <footer><button type="button" onClick={() => setNoteEvent(null)}>확인</button></footer>
      </section>
    </div>}
  </section>;
}

function AcademicEditor({ row, initialDate, initialScope, data, supabase, profile, onClose, onSaved }: { row: EventRow | null; initialDate: string; initialScope: Scope; data: Board; supabase: SupabaseClient; profile: Profile; onClose: () => void; onSaved: () => Promise<void> }) {
  const initialCategory = row?.category ?? data.categories.find(item => item.scope === initialScope && item.active)?.id ?? "";
  const [v, setV] = useState({
    scope: row?.scope ?? initialScope, school: row?.school ?? "", grade: row?.grade ?? "",
    category: initialCategory,
    title: row?.title ?? "", startsOn: row?.startsOn ?? initialDate, endsOn: row?.endsOn ?? initialDate,
    hasTime: Boolean(row?.startsAt), startsAt: row?.startsAt?.slice(0, 5) ?? "17:30", endsAt: row?.endsAt?.slice(0, 5) ?? "19:00",
    classId: row?.classId ?? "", teacherId: row?.teacherId ?? profile.id, note: row?.note ?? "",
    contactName: row?.contactName ?? "", contactPhone: row?.contactPhone ?? "", location: row?.location ?? "",
    status: row?.status ?? "scheduled" as Status,
  });
  const [baseline,setBaseline]=useState(()=>row?calendarValues(row):null);
  const busy=useRef(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const update = (key: string, value: string | boolean) => setV(current => ({ ...current, [key]: value }));
  const options = data.categories.filter(item => item.scope === v.scope && (item.active || item.id === row?.category));
  const changeScope = (scope: Scope) => setV(current => ({ ...current, scope, category: data.categories.find(item => item.scope === scope && item.active)?.id ?? "" }));
  const save = async (event: FormEvent) => {
    event.preventDefault(); if(busy.current)return; busy.current=true;setSaving(true); setError("");
    try {
    if(row&&baseline){
      const mine=calendarValues({...v,startsAt:v.hasTime?v.startsAt:null,endsAt:v.hasTime?v.endsAt:null,status:v.scope==="academy"?v.status:"scheduled"});
      const {data:result,error:failure}=await supabase.rpc("staff_patch_calendar_event",{p_id:row.id,p_base:baseline,p_changes:settingsChanges(baseline,mine)});
      if(failure)throw failure;
      if(result.conflicts?.length){
        const latest=result.values as typeof mine;
        const labels:Record<string,string>={kind:"일정 구분·종류",timing:"날짜·시간",school:"학교",grade:"학년",title:"일정명",classId:"연결 클래스",teacherId:"담당 선생님",note:"메모",contactName:"학생·상담자",contactPhone:"연락처",location:"장소",status:"진행 상태"};
        const format=(key:string,value:unknown)=>{if(key==="kind"){const x=value as typeof mine.kind;return `${x.scope==="school"?"학교":"학원"} · ${data.categories.find(c=>c.id===x.category)?.label??x.category}`;}if(key==="timing"){const x=value as typeof mine.timing;return `${x.startsOn} ~ ${x.endsOn} · ${x.startsAt?`${x.startsAt}–${x.endsAt}`:"종일"}`;}if(key==="classId")return data.classes.find(x=>x.id===value)?.name??"연결 안 함";if(key==="teacherId")return data.teachers.find(x=>x.id===value)?.name??"담당 없음";if(key==="status")return statusLabel(String(value) as Status);return String(value||"미입력");};
        const choices=await compareEdits(result.conflicts.map((key:keyof typeof mine)=>({id:key,student:row.title,field:labels[key]??key,mine:format(key,mine[key]),latest:format(key,latest[key])})));
        if(choices){const merged=mergeSettingsChoices(baseline,mine,latest,choices);setBaseline(latest);setV({...v,...merged,...merged.kind,...merged.timing,scope:merged.kind.scope as Scope,status:merged.status as Status,hasTime:Boolean(merged.timing.startsAt)});setError("선택한 내용을 적용했습니다. 확인 후 다시 저장해 주세요.");}
        return;
      }
      await onSaved();return;
    }
    const { error: saveError } = await supabase.rpc("staff_save_calendar_event", {
      p_id: row?.id ?? null, p_scope: v.scope, p_school: v.school || null, p_grade: v.grade || null,
      p_category: v.category, p_title: v.title, p_starts_on: v.startsOn, p_ends_on: v.endsOn,
      p_starts_at: v.hasTime ? v.startsAt : null, p_ends_at: v.hasTime ? v.endsAt : null,
      p_class_id: v.classId || null, p_teacher_id: v.teacherId || null, p_note: v.note || null,
      p_contact_name: v.contactName || null, p_contact_phone: v.contactPhone || null,
      p_location: v.location || null, p_status: v.scope === "academy" ? v.status : "scheduled",
    });
    if (saveError) throw saveError; else await onSaved();
    } catch(e){setError((e as {message?:string}).message??"일정 저장에 실패했습니다.");} finally {busy.current=false;setSaving(false);}
  };
  const remove = async () => {
    if (busy.current || !row || !await appConfirm({ eyebrow: "일정 삭제", title: `‘${row.title}’ 일정을 삭제할까요?`, copy: `${row.startsOn}${row.endsOn !== row.startsOn ? ` ~ ${row.endsOn}` : ""}`, notice: "삭제한 일정은 캘린더에서 즉시 사라집니다.", confirmLabel: "일정 삭제", tone: "danger" })) return;
    if(busy.current)return;busy.current=true;setSaving(true);
    try{const {data:result,error:removeError}=await supabase.rpc("staff_patch_calendar_event",{p_id:row.id,p_base:baseline,p_changes:{},p_delete:true});
      if(removeError)throw removeError;
      if(result.conflicts?.length){setError("다른 선생님이 수정한 일정입니다. 창을 다시 열어 최신 내용을 확인한 뒤 삭제해 주세요.");return;}
      await onSaved();
    }catch(e){setError((e as {message?:string}).message??"삭제에 실패했습니다.");}finally{busy.current=false;setSaving(false);}
  };

  return <div className="modal-backdrop"><form className="student-modal academic-editor" onSubmit={save} inert={saving}>
    <header><div><p className="eyebrow">한살매 통합 일정</p><h2>{row ? "일정 수정" : "새 일정 등록"}</h2><span>학교 학사일정과 학원 운영 일정을 한곳에 기록합니다.</span></div><button type="button" onClick={onClose}>×</button></header>
    <div className="academic-editor-scope">
      <button type="button" className={v.scope === "school" ? "active" : ""} onClick={() => changeScope("school")}>학교 일정</button>
      <button type="button" className={v.scope === "academy" ? "active" : ""} onClick={() => changeScope("academy")}>학원 일정</button>
    </div>
    <div className="academic-form">
      <label>일정 종류 *<select value={v.category} onChange={event => update("category", event.target.value)}>{options.map(x => <option value={x.id} key={x.id}>{x.label}</option>)}</select></label>
      <label>일정명 *<input required value={v.title} onChange={event => update("title", event.target.value)} placeholder={v.scope === "academy" ? "예: 신규 상담, 중2 영어 청강" : "예: 2학기 중간고사"} /></label>
      {v.scope === "academy" && <><label>학생·상담자 이름<input value={v.contactName} onChange={event => update("contactName", event.target.value)} placeholder="이름 입력" /></label><label>연락처<input value={v.contactPhone} onChange={event => update("contactPhone", event.target.value)} placeholder="010-0000-0000" /></label></>}
      <label>{v.scope === "school" ? "학교 *" : "학교"}<input required={v.scope === "school"} list="academic-schools" value={v.school} onChange={event => update("school", event.target.value)} placeholder={v.scope === "school" ? "학교 이름 입력" : "해당하는 경우 입력"} /><datalist id="academic-schools">{data.schools.map(x => <option key={x} value={x} />)}</datalist></label>
      <label>학년<select value={v.grade} onChange={event => update("grade", event.target.value)}><option value="">학년 선택 안 함</option>{grades.map(x => <option key={x}>{x}</option>)}</select></label>
      <label>시작일 *<input required type="date" value={v.startsOn} onChange={event => update("startsOn", event.target.value)} /></label>
      <label>종료일 *<input required type="date" value={v.endsOn} onChange={event => update("endsOn", event.target.value)} /></label>
      <label className="academic-time-check"><input type="checkbox" checked={v.hasTime} onChange={event => update("hasTime", event.target.checked)} /> 시간 지정</label>
      {v.hasTime && <><label>시작 시간<input required type="time" value={v.startsAt} onChange={event => update("startsAt", event.target.value)} /></label><label>종료 시간<input required type="time" value={v.endsAt} onChange={event => update("endsAt", event.target.value)} /></label></>}
      {v.scope === "academy" && <><label>장소<input value={v.location} onChange={event => update("location", event.target.value)} placeholder="예: 상담실, 2강의실" /></label><label>진행 상태<select value={v.status} onChange={event => update("status", event.target.value)}>{statuses.map(x => <option value={x.id} key={x.id}>{x.label}</option>)}</select></label></>}
      <label>연결 클래스<select value={v.classId} onChange={event => update("classId", event.target.value)}><option value="">연결 안 함</option>{data.classes.map(x => <option value={x.id} key={x.id}>{x.name} · {x.subject}</option>)}</select></label>
      <label>담당 선생님<select value={v.teacherId} onChange={event => update("teacherId", event.target.value)}>{data.teachers.map(x => <option value={x.id} key={x.id}>{x.name}</option>)}</select></label>
      <label className="academic-note">메모<textarea value={v.note} onChange={event => update("note", event.target.value)} placeholder={v.scope === "academy" ? "상담 내용, 청강 과목, 준비사항 등을 적어주세요." : "시험 범위, 준비물, 보강 대상 등을 적어주세요."} /></label>
    </div>
    {error && <p className="form-error">{error}</p>}
    <footer>{row && <button type="button" className="danger-link" onClick={() => void remove()}>삭제</button>}<span /><button type="button" className="secondary-button" onClick={onClose}>취소</button><button className="primary" disabled={saving}>{saving ? "저장 중…" : "일정 저장"}</button></footer>
  </form></div>;
}

function AcademicCategoryManager({ categories, supabase, onClose, onChanged }: { categories: CalendarCategory[]; supabase: SupabaseClient; onClose: () => void; onChanged: () => Promise<void> }) {
  const [scope, setScope] = useState<Scope>("school");
  const [newLabel, setNewLabel] = useState("");
  const [names, setNames] = useState<Record<string, string>>(() => Object.fromEntries(categories.map(item => [item.id, item.label])));
  const [savingId, setSavingId] = useState("");
  const [error, setError] = useState("");
  const rows = categories.filter(item => item.scope === scope);
  const add = async () => {
    if (!newLabel.trim()) return;
    setSavingId("new"); setError("");
    const { error: saveError } = await supabase.rpc("admin_save_academic_calendar_category", { p_id: null, p_scope: scope, p_label: newLabel.trim() });
    if (saveError) setError(saveError.message); else { setNewLabel(""); await onChanged(); }
    setSavingId("");
  };
  const rename = async (row: CalendarCategory) => {
    const next = names[row.id]?.trim();
    if (!next || next === row.label) return;
    setSavingId(row.id); setError("");
    const { error: saveError } = await supabase.rpc("admin_save_academic_calendar_category", { p_id: row.id, p_scope: row.scope, p_label: next });
    if (saveError) setError(saveError.message); else await onChanged();
    setSavingId("");
  };
  const toggle = async (row: CalendarCategory) => {
    if (row.active && !await appConfirm({ eyebrow: "카테고리 삭제", title: `‘${row.label}’을 삭제할까요?`, copy: "새 일정의 선택 목록에서 제외됩니다.", notice: "이미 등록된 일정에는 기존 카테고리 이름이 그대로 보존됩니다.", confirmLabel: "카테고리 삭제", tone: "danger" })) return;
    setSavingId(row.id); setError("");
    const { error: saveError } = await supabase.rpc("admin_set_academic_calendar_category_active", { p_id: row.id, p_active: !row.active });
    if (saveError) setError(saveError.message); else await onChanged();
    setSavingId("");
  };
  return <div className="modal-backdrop"><section className="student-modal academic-category-manager" role="dialog" aria-modal="true" aria-labelledby="academic-category-title">
    <header><div><p className="eyebrow">관리자 설정</p><h2 id="academic-category-title">일정 카테고리 관리</h2><span>학교 일정과 학원 일정의 종류를 각각 관리합니다.</span></div><button type="button" aria-label="닫기" onClick={onClose}>×</button></header>
    <nav><button className={scope === "school" ? "active" : ""} onClick={() => setScope("school")}>학교 일정</button><button className={scope === "academy" ? "active" : ""} onClick={() => setScope("academy")}>학원 일정</button></nav>
    <div className="academic-category-add"><input maxLength={30} value={newLabel} onChange={event => setNewLabel(event.target.value)} onKeyDown={event => { if (event.key === "Enter") { event.preventDefault(); void add(); } }} placeholder="새 카테고리 이름"/><button className="primary" disabled={savingId === "new" || !newLabel.trim()} onClick={() => void add()}>추가</button></div>
    <div className="academic-category-list">{rows.map(row => { const changed = (names[row.id]?.trim() ?? "") !== row.label; return <article className={row.active ? "" : "inactive"} key={row.id}><input maxLength={30} value={names[row.id] ?? row.label} disabled={!row.active} onChange={event => setNames(current => ({ ...current, [row.id]: event.target.value }))}/><span>{row.active ? <>{changed && <button className="secondary-button" disabled={savingId === row.id || !names[row.id]?.trim()} onClick={() => void rename(row)}>이름 저장</button>}<button className="danger-button" disabled={savingId === row.id} onClick={() => void toggle(row)}>삭제</button></> : <><em>삭제됨</em><button className="secondary-button" disabled={savingId === row.id} onClick={() => void toggle(row)}>복구</button></>}</span></article> })}</div>
    {error && <p className="form-error">{error}</p>}
    <footer><span>삭제된 카테고리도 과거 일정에는 그대로 표시됩니다.</span><button className="primary" onClick={onClose}>완료</button></footer>
  </section></div>;
}

function calendarEventText(event: EventRow) {
  if (event.scope === "academy") return event.contactName ? `${event.categoryLabel} · ${event.contactName}` : event.title;
  return `${event.school ?? "학교"} · ${event.title}`;
}
function calendarDays(month: string) { const [y, m] = month.split("-").map(Number), first = new Date(y, m - 1, 1).getDay(), last = new Date(y, m, 0).getDate(); return [...Array(first).fill(null), ...Array.from({ length: last }, (_, i) => i + 1), ...Array(42 - first - last).fill(null)] as (number | null)[]; }
function toDate(date: Date) { return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}-${String(date.getDate()).padStart(2, "0")}`; }
function statusLabel(status: Status) { return statuses.find(x => x.id === status)?.label ?? "예약·예정"; }
function formatDate(value: string) { return new Intl.DateTimeFormat("ko-KR", { month: "long", day: "numeric", weekday: "long" }).format(new Date(`${value}T00:00:00`)); }
function weekdayName(value: string) { return new Intl.DateTimeFormat("ko-KR", { weekday: "long" }).format(new Date(`${value}T00:00:00`)); }
function fixedHolidays(year: number): Holiday[] { return [[`${year}-01-01`, "신정"], [`${year}-03-01`, "삼일절"], [`${year}-05-05`, "어린이날"], [`${year}-06-06`, "현충일"], [`${year}-08-15`, "광복절"], [`${year}-10-03`, "개천절"], [`${year}-10-09`, "한글날"], [`${year}-12-25`, "성탄절"]].map(([date, localName]) => ({ date, localName })); }
