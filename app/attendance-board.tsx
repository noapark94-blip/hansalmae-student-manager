"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type AttendanceStatus = "present" | "late" | "absent" | "excused";
type AttendanceStudent = { id: string; name: string; status: AttendanceStatus | null; note: string | null; makeupRequired: boolean };
type AttendanceClass = { scheduleId: string; classId: string; className: string; subject: string; room: string | null; color: string; startTime: string; endTime: string; students: AttendanceStudent[] };
type Preparation = { createdLessons: number; lessonCount: number; studentCount: number };

const statusOptions: { id: AttendanceStatus; label: string }[] = [
  { id: "present", label: "출석" },
  { id: "late", label: "지각" },
  { id: "absent", label: "결석" },
  { id: "excused", label: "공결" },
];

export function AttendanceBoard({ supabase }: { supabase: SupabaseClient }) {
  const [date, setDate] = useState(koreaToday());
  const [classes, setClasses] = useState<AttendanceClass[]>([]);
  const [selectedId, setSelectedId] = useState("");
  const [loading, setLoading] = useState(true);
  const [savingId, setSavingId] = useState("");
  const [error, setError] = useState("");
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [preparation, setPreparation] = useState<Preparation | null>(null);

  const load = useCallback(async () => {
    setLoading(true); setError("");
    const { data: prepared, error: prepareError } = await supabase.rpc("staff_prepare_daily_attendance", { p_date: date });
    if (prepareError) {
      setError("출석부를 자동 준비하지 못했습니다. DB 업데이트를 확인해 주세요.");
      setPreparation(null); setLoading(false); return;
    }
    setPreparation(prepared as Preparation);
    const { data, error: loadError } = await supabase.rpc("staff_attendance_board", { p_date: date });
    if (loadError) setError("수업과 학생 명단을 불러오지 못했습니다.");
    else {
      const next = (data ?? []) as AttendanceClass[];
      setClasses(next);
      setSelectedId((current) => next.some((item) => item.scheduleId === current) ? current : next[0]?.scheduleId ?? "");
      setNotes(Object.fromEntries(next.flatMap((item) => item.students.map((student) => [student.id, student.note ?? ""]))));
    }
    setLoading(false);
  }, [date, supabase]);

  useEffect(() => { void load(); }, [load]);
  const selected = classes.find((item) => item.scheduleId === selectedId);
  const totals = useMemo(() => selected?.students.reduce((result, student) => ({ ...result, [student.status ?? "unchecked"]: result[student.status ?? "unchecked"] + 1 }), { present: 0, late: 0, absent: 0, excused: 0, unchecked: 0 } as Record<AttendanceStatus | "unchecked", number>), [selected]);

  const save = async (student: AttendanceStudent, status: AttendanceStatus) => {
    if (!selected) return;
    setSavingId(student.id); setError("");
    const { error: saveError } = await supabase.rpc("staff_save_attendance", { p_schedule_id: selected.scheduleId, p_date: date, p_student_id: student.id, p_status: status, p_note: notes[student.id] ?? null });
    if (saveError) setError("출결을 저장하지 못했습니다. 잠시 후 다시 시도해 주세요.");
    else setClasses((current) => current.map((item) => item.scheduleId !== selected.scheduleId ? item : { ...item, students:item.students.map((row) => row.id === student.id ? { ...row, status, note:notes[row.id] ?? null, makeupRequired:status === "absent" } : row) }));
    setSavingId("");
  };

  const markAllPresent = async () => {
    if (!selected || !confirm(`${selected.className} 학생을 모두 출석으로 표시할까요?`)) return;
    setSavingId("all"); setError("");
    const { error: saveError } = await supabase.rpc("staff_mark_class_present", { p_schedule_id: selected.scheduleId, p_date: date });
    if (saveError) setError("전체 출석을 저장하지 못했습니다."); else await load();
    setSavingId("");
  };

  return <>
    <div className="page-heading compact"><div><p className="eyebrow">수업별 실시간 기록</p><h1>출결·보강</h1><p>출석 상태를 선택하면 홈 화면 집계와 결석 학생의 보강 필요 건수에 바로 반영됩니다.</p></div><label className="attendance-date">수업 날짜<input type="date" value={date} onChange={(event) => setDate(event.target.value)} /></label></div>
    {error && <p className="attendance-error">{error}</p>}
    {!loading && preparation && <p className="attendance-prepared">✓ 시간표 기준 출석부 준비 완료 · 수업 {preparation.lessonCount}개 · 명단 {preparation.studentCount}명{preparation.createdLessons > 0 ? ` · 새로 생성 ${preparation.createdLessons}개` : ""}</p>}
    {loading ? <section className="panel attendance-empty">수업 명단을 불러오는 중이에요…</section> : classes.length === 0 ? <section className="panel attendance-empty">선택한 날짜에 등록된 수업이 없습니다.</section> : <>
      <div className="attendance-class-tabs">{classes.map((item) => <button className={selectedId === item.scheduleId ? "active" : ""} key={item.scheduleId} onClick={() => setSelectedId(item.scheduleId)} style={{ borderTopColor:item.color }}><b>{item.startTime.slice(0,5)}</b><span>{item.className}</span><small>{item.room ?? "강의실 미지정"}</small></button>)}</div>
      {selected && <section className="panel attendance-panel"><header><div><h2>{selected.className}</h2><span>{selected.startTime.slice(0,5)}–{selected.endTime.slice(0,5)} · {selected.subject}{selected.room ? ` · ${selected.room}` : ""}</span></div><button className="secondary-button" disabled={savingId === "all"} onClick={() => void markAllPresent()}>✓ 전체 출석</button></header><div className="attendance-summary"><span>출석 <b>{totals?.present ?? 0}</b></span><span>지각 <b>{totals?.late ?? 0}</b></span><span>결석 <b>{totals?.absent ?? 0}</b></span><span>공결 <b>{totals?.excused ?? 0}</b></span><span>미입력 <b>{totals?.unchecked ?? 0}</b></span></div><div className="attendance-list">{selected.students.length === 0 ? <p className="attendance-empty">이 클래스에 배정된 재원생이 없습니다.</p> : selected.students.map((student) => <article key={student.id}><div className="attendance-student"><i>{student.name.slice(0,1)}</i><b>{student.name}</b>{student.makeupRequired && <em>보강 필요</em>}</div><div className="attendance-statuses">{statusOptions.map((option) => <button key={option.id} disabled={savingId === student.id} className={`${option.id}${student.status === option.id ? " active" : ""}`} onClick={() => void save(student, option.id)}>{option.label}</button>)}</div><input className="attendance-note" value={notes[student.id] ?? ""} onChange={(event) => setNotes((current) => ({ ...current, [student.id]:event.target.value }))} onBlur={() => { if (student.status && notes[student.id] !== (student.note ?? "")) void save(student, student.status); }} placeholder="메모 (선택)" /></article>)}</div></section>}
    </>}
  </>;
}

function koreaToday() { const parts = new Intl.DateTimeFormat("en", { timeZone:"Asia/Seoul", year:"numeric", month:"2-digit", day:"2-digit" }).formatToParts(new Date()); const value = Object.fromEntries(parts.map((part) => [part.type, part.value])); return `${value.year}-${value.month}-${value.day}`; }
