"use client";

import { useCallback, useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type Status = "present" | "late" | "absent";
type ExamCategory = { id: string; name: string; isActive: boolean; sortOrder: number };
type Exam = { examType: string; examTitle: string; score: string; maxScore: string; evaluation: string };
type Row = {
  id: string; name: string; school: string | null; grade: string | null;
  status: Status | null; lateMinutes: number | null; absenceReason: string | null;
  assignedHomework: string; previousHomework: string; inspectionStatus: string; inspectionNote: string; exam: Exam;
};
type Board = { notice: string; students: Array<Omit<Row, "exam"> & { exam?: Partial<Record<keyof Exam, string | number | null>> }> };

const attendance: [Status, string][] = [["present", "출석"], ["late", "지각"], ["absent", "결석"]];
const homework = [["", "미검사"], ["complete", "완료"], ["partial", "일부"], ["missing", "미제출"], ["excused", "면제"]];

export function SpecialLessonLearningBoard({ supabase, sessionId, onClose, onEdit, embedded = false }: { supabase: SupabaseClient; sessionId: string; onClose: () => void; onEdit: () => void; embedded?: boolean }) {
  const [rows, setRows] = useState<Row[]>([]);
  const [notice, setNotice] = useState("");
  const [categories, setCategories] = useState<ExamCategory[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState("");
  const [error, setError] = useState("");
  const load = useCallback(async () => {
    setLoading(true);
    const [boardResponse, categoryResponse] = await Promise.all([
      supabase.rpc("staff_special_lesson_board", { p_session_id: sessionId }),
      supabase.rpc("staff_exam_categories"),
    ]);
    if (boardResponse.error || categoryResponse.error) setError(boardResponse.error?.message ?? categoryResponse.error?.message ?? "수업 기록을 불러오지 못했습니다.");
    else {
      const board = boardResponse.data as Board;
      setNotice(board?.notice ?? "");
      setRows((board?.students ?? []).map((row) => ({ ...row, exam: {
        examType: String(row.exam?.examType ?? ""), examTitle: String(row.exam?.examTitle ?? ""),
        score: row.exam?.score == null ? "" : String(row.exam.score), maxScore: row.exam?.maxScore == null ? "100" : String(row.exam.maxScore),
        evaluation: String(row.exam?.evaluation ?? ""),
      }})));
      setCategories((categoryResponse.data ?? []) as ExamCategory[]);
      setError("");
    }
    setLoading(false);
  }, [sessionId, supabase]);
  useEffect(() => void load(), [load]);
  const update = (id: string, patch: Partial<Row>) => setRows((current) => current.map((row) => row.id === id ? { ...row, ...patch } : row));
  const updateExam = (id: string, patch: Partial<Exam>) => setRows((current) => current.map((row) => row.id === id ? { ...row, exam: { ...row.exam, ...patch } } : row));
  const saveAttendance = async (row: Row, status: Status) => {
    setSaving(row.id); setError("");
    const next = row.status === status ? null : status;
    let late: number | null = null, reason: string | null = null;
    if (next === "late") { const value = prompt(`${row.name} 학생은 몇 분 지각했나요?`, String(row.lateMinutes ?? 10)); if (value === null) return setSaving(""); late = Number(value); if (!Number.isFinite(late) || late < 1) { setSaving(""); return setError("지각 시간을 숫자로 입력해 주세요."); } }
    if (next === "absent") { const value = prompt(`${row.name} 학생의 결석 사유`, row.absenceReason ?? ""); if (value === null) return setSaving(""); reason = value.trim(); if (!reason) { setSaving(""); return setError("결석 사유를 입력해 주세요."); } }
    const { error: saveError } = await supabase.rpc("staff_save_special_lesson_attendance", { p_session_id: sessionId, p_student_id: row.id, p_status: next, p_late_minutes: late, p_absence_reason: reason });
    if (saveError) setError(saveError.message); else update(row.id, { status: next, lateMinutes: late, absenceReason: reason });
    setSaving("");
  };
  const save = async () => {
    for (const row of rows) { const score = Number(row.exam.score), max = Number(row.exam.maxScore); if (row.exam.score !== "" && (!Number.isFinite(score) || !Number.isFinite(max) || max <= 0 || score < 0 || score > max)) return setError(`${row.name} 학생의 점수를 확인해 주세요.`); }
    setSaving("all"); setError("");
    const { error: saveError } = await supabase.rpc("staff_save_special_lesson_learning", { p_session_id: sessionId, p_notice: notice, p_rows: rows.map((row) => ({ studentId: row.id, assignedHomework: row.assignedHomework, inspectionStatus: row.inspectionStatus, inspectionNote: row.inspectionNote, exam: { ...row.exam, score: row.exam.score === "" ? null : +row.exam.score, maxScore: +row.exam.maxScore } })) });
    if (saveError) setError(saveError.message); else await load();
    setSaving("");
  };
  return <section className={`${embedded ? "class-learning-board special-board-embedded" : "student-modal"} special-board-modal`}>
    <header><div><p className="eyebrow">개별 보강·추가수업</p><h2>수업 기록</h2><span>학생별 출결·시험·지난 숙제 검사·오늘 숙제를 한 화면에서 기록합니다.</span></div><button className="secondary-button" onClick={onClose}>{embedded ? "일정 목록" : "×"}</button></header>
    <div className="special-board-toolbar"><button className="secondary-button" onClick={onEdit}>학생·시간 수정</button></div>
    <label className="class-daily-notice"><b>수업 공지사항</b><textarea value={notice} onChange={(event) => setNotice(event.target.value)} placeholder="준비물·수업 안내" rows={2} /></label>
    <div className="learning-board-heading"><span>학생·출결</span><span>개인별 시험</span><span>지난 숙제 검사</span><span>오늘 내줄 숙제</span></div>
    {loading ? <p className="settings-empty">불러오는 중이에요…</p> : <div className="learning-board-rows">{rows.map((row) => {
      const score = Number(row.exam.score), max = Number(row.exam.maxScore), converted = row.exam.score !== "" && max > 0 ? Math.round(score / max * 1000) / 10 : null;
      return <article key={row.id}>
        <div className="learning-person-attendance"><span className="learning-student"><i>{row.name[0]}</i><b>{row.name}</b><small>{[row.school,row.grade].filter(Boolean).join(" · ")}</small></span><div className="learning-attendance">{attendance.map(([status,label]) => <button key={status} className={`${status} ${row.status === status ? "active" : ""}`} disabled={saving===row.id} onClick={() => void saveAttendance(row,status)}>{label}</button>)}{row.status === "late" ? <small>{row.lateMinutes}분 지각</small> : null}{row.status === "absent" ? <small>{row.absenceReason}</small> : null}</div></div>
        <div className="learning-exam individual"><select value={row.exam.examType} onChange={(event) => updateExam(row.id,{examType:event.target.value})}><option value="">종류 선택</option>{categories.filter((item)=>item.isActive).map((item)=><option key={item.id}>{item.name}</option>)}</select><input value={row.exam.examTitle} onChange={(event)=>updateExam(row.id,{examTitle:event.target.value})} placeholder="시험명·범위"/><span><input inputMode="decimal" value={row.exam.score} onChange={(event)=>updateExam(row.id,{score:event.target.value})} placeholder="원점수"/><em>/</em><input inputMode="decimal" value={row.exam.maxScore} onChange={(event)=>updateExam(row.id,{maxScore:event.target.value})}/></span><input value={row.exam.evaluation} onChange={(event)=>updateExam(row.id,{evaluation:event.target.value})} placeholder="평가·피드백"/>{converted == null ? null : <small>환산 {converted}점</small>}</div>
        <div className="learning-homework previous"><p>{row.previousHomework || "지난 숙제 없음"}</p><select value={row.inspectionStatus} onChange={(event)=>update(row.id,{inspectionStatus:event.target.value})}>{homework.map(([value,label])=><option key={value} value={value}>{label}</option>)}</select><input value={row.inspectionNote} onChange={(event)=>update(row.id,{inspectionNote:event.target.value})} placeholder="검사 메모"/></div>
        <div className="learning-homework assigned"><input value={row.assignedHomework} onChange={(event)=>update(row.id,{assignedHomework:event.target.value})} placeholder="교재·페이지·문제 번호·제출일"/></div>
      </article>;
    })}{!rows.length ? <p className="settings-empty">배정된 학생이 없습니다. 학생·시간 수정에서 학생을 추가해 주세요.</p> : null}</div>}
    {error ? <p className="form-error learning-board-error">{error}</p> : null}
    <footer><span>출결은 즉시 저장되고 시험·숙제·공지는 아래 버튼으로 저장됩니다.</span><button className="primary" disabled={saving==="all"} onClick={() => void save()}>{saving==="all" ? "저장 중…" : "시험·숙제 한 번에 저장"}</button></footer>
  </section>;
}
