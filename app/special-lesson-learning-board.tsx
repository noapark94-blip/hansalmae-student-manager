"use client";

import { useCallback, useEffect, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type Status = "present" | "late" | "absent";
type ExamCategory = { id: string; name: string; isActive: boolean; sortOrder: number };
type Exam = { examType: string; examTitle: string; score: string; maxScore: string; evaluation: string };
type Row = {
  id: string; name: string; school: string | null; grade: string | null;
  status: Status | null; lateMinutes: number | null; absenceReason: string | null;
  lessonContent: string; assignedHomework: string; previousHomework: string; inspectionStatus: string; inspectionNote: string; exam: Exam;
};
type Board = { notice: string; state: "draft" | "completed"; students: Array<Omit<Row, "exam"> & { exam?: Partial<Record<keyof Exam, string | number | null>> }> };
type FamilyReadStudent = { studentId:string; studentName:string; school:string|null; grade:string|null; guardianCount:number; readCount:number; status:"confirmed"|"unconfirmed"|"unlinked"; viewedAt:string|null };
type FamilyReadStatus = { lessonId:string|null; totalStudents:number; linkedStudents:number; confirmedStudents:number; unconfirmedStudents:number; unlinkedStudents:number; students:FamilyReadStudent[] };

const attendance: [Status, string][] = [["present", "출석"], ["late", "지각"], ["absent", "결석"]];
const homework = [["", "미검사"], ["complete", "완료"], ["partial", "일부"], ["missing", "미제출"], ["excused", "면제"]];

export function SpecialLessonLearningBoard({ supabase, sessionId, onClose, onAttendanceChange, embedded = false }: { supabase: SupabaseClient; sessionId: string; onClose: () => void; onEdit: () => void; onAttendanceChange?: () => void | Promise<void>; embedded?: boolean }) {
  const [rows, setRows] = useState<Row[]>([]);
  const [notice, setNotice] = useState("");
  const [categories, setCategories] = useState<ExamCategory[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState("");
  const [error, setError] = useState("");
  const [categoryManager, setCategoryManager] = useState(false);
  const [newCategoryName, setNewCategoryName] = useState("");
  const [categorySaving, setCategorySaving] = useState(false);
  const [lessonState, setLessonState] = useState<"draft" | "completed">("draft");
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
      setLessonState(board?.state === "completed" ? "completed" : "draft");
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
  useEffect(() => {
    const closeTopLayer = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      if (categoryManager) setCategoryManager(false);
      else onClose();
    };
    document.addEventListener("keydown", closeTopLayer);
    return () => document.removeEventListener("keydown", closeTopLayer);
  }, [categoryManager, onClose]);
  const refreshCategories = async () => {
    const { data, error: categoryError } = await supabase.rpc("staff_exam_categories");
    if (categoryError) setError(categoryError.message);
    else setCategories((data ?? []) as ExamCategory[]);
  };
  const addCategory = async () => {
    const name = newCategoryName.trim();
    if (!name) return setError("추가할 시험 종류 이름을 입력해 주세요.");
    setCategorySaving(true); setError("");
    const { error: categoryError } = await supabase.rpc("staff_add_exam_category", { p_name: name });
    if (categoryError) setError(categoryError.message);
    else { setNewCategoryName(""); await refreshCategories(); }
    setCategorySaving(false);
  };
  const removeCategory = async (category: ExamCategory) => {
    if (!confirm(`시험 종류 '${category.name}'을 목록에서 삭제할까요? 기존 시험 기록은 유지됩니다.`)) return;
    setCategorySaving(true); setError("");
    const { error: categoryError } = await supabase.rpc("staff_set_exam_category", { p_id: category.id, p_name: category.name, p_active: false });
    if (categoryError) setError(categoryError.message); else await refreshCategories();
    setCategorySaving(false);
  };
  const update = (id: string, patch: Partial<Row>) => setRows((current) => current.map((row) => row.id === id ? { ...row, ...patch } : row));
  const updateExam = (id: string, patch: Partial<Exam>) => setRows((current) => current.map((row) => row.id === id ? { ...row, exam: { ...row.exam, ...patch } } : row));
  const saveAttendance = async (row: Row, status: Status) => {
    setSaving(row.id); setError("");
    const next = row.status === status ? null : status;
    let late: number | null = null, reason: string | null = null;
    if (next === "late") { const value = prompt(`${row.name} 학생은 몇 분 지각했나요?`, String(row.lateMinutes ?? 10)); if (value === null) return setSaving(""); late = Number(value); if (!Number.isFinite(late) || late < 1) { setSaving(""); return setError("지각 시간을 숫자로 입력해 주세요."); } }
    if (next === "absent") { const value = prompt(`${row.name} 학생의 결석 사유`, row.absenceReason ?? ""); if (value === null) return setSaving(""); reason = value.trim(); if (!reason) { setSaving(""); return setError("결석 사유를 입력해 주세요."); } }
    const { error: saveError } = await supabase.rpc("staff_save_special_lesson_attendance", { p_session_id: sessionId, p_student_id: row.id, p_status: next, p_late_minutes: late, p_absence_reason: reason });
    if (saveError) setError(saveError.message); else { update(row.id, { status: next, lateMinutes: late, absenceReason: reason }); await onAttendanceChange?.(); }
    setSaving("");
  };
  const save = async (complete: boolean) => {
    if (complete) { const missing = rows.filter((row) => !row.status).map((row) => row.name); if (missing.length) return setError(`출결 미입력 학생: ${missing.join(", ")}`); }
    for (const row of rows) { const score = Number(row.exam.score), max = Number(row.exam.maxScore); if (row.exam.score !== "" && (!Number.isFinite(score) || !Number.isFinite(max) || max <= 0 || score < 0 || score > max)) return setError(`${row.name} 학생의 점수를 확인해 주세요.`); }
    setSaving("all"); setError("");
    const { error: saveError } = await supabase.rpc("staff_save_special_lesson_learning", { p_session_id: sessionId, p_notice: notice, p_rows: rows.map((row) => ({ studentId: row.id, lessonContent: row.lessonContent, assignedHomework: row.assignedHomework, inspectionStatus: row.inspectionStatus, inspectionNote: row.inspectionNote, exam: { ...row.exam, score: row.exam.score === "" ? null : +row.exam.score, maxScore: +row.exam.maxScore } })) });
    if (saveError) setError(saveError.message); else {
      const { data: stateData, error: stateError } = await supabase.rpc("staff_set_special_lesson_state", { p_session_id: sessionId, p_state: complete ? "completed" : "draft" });
      if (stateError) setError(stateError.message); else { setLessonState(stateData === "completed" ? "completed" : "draft"); await Promise.all([load(), onAttendanceChange?.()]); }
    }
    setSaving("");
  };
  return <section className={`${embedded ? "class-learning-board special-board-embedded" : "student-modal"} special-board-modal`}>
    <SpecialFamilyReportReadStatus supabase={supabase} sessionId={sessionId} />
    <div className="learning-board-scroll"><div className="learning-board-table"><div className="learning-board-heading"><span>학생·출결</span><span>개인별 수업 내용</span><span className="learning-exam-heading"><b>개인별 시험</b><button type="button" onClick={() => setCategoryManager(true)}>시험 카테고리 관리</button></span><span>지난 숙제 검사</span><span>오늘 내줄 숙제</span></div>
    {loading ? <p className="settings-empty">불러오는 중이에요…</p> : <div className="learning-board-rows">{rows.map((row) => {
      const score = Number(row.exam.score), max = Number(row.exam.maxScore), converted = row.exam.score !== "" && max > 0 ? Math.round(score / max * 1000) / 10 : null;
      return <article key={row.id}>
        <div className="learning-person-attendance"><span className="learning-student"><i>{row.name[0]}</i><b>{row.name}</b><small>{[row.school,row.grade].filter(Boolean).join(" · ")}</small></span><div className="learning-attendance">{attendance.map(([status,label]) => <button type="button" key={status} className={`${status} ${row.status === status ? "active" : ""}`} disabled={saving===row.id} onClick={() => void saveAttendance(row,status)}>{label}</button>)}{row.status ? <small>{row.status === "late" ? `${row.lateMinutes}분 지각 · ` : row.status === "absent" && row.absenceReason ? `${row.absenceReason} · ` : ""}같은 버튼을 다시 누르면 취소</small> : null}</div></div>
        <div className="learning-individual-content"><textarea value={row.lessonContent} onChange={(event) => update(row.id,{lessonContent:event.target.value})} placeholder="이 학생의 교재·단원·진도" rows={4}/></div>
        <div className="learning-exam individual"><select value={row.exam.examType} onChange={(event) => updateExam(row.id,{examType:event.target.value})}><option value="">종류 선택</option>{categories.filter((item)=>item.isActive).map((item)=><option key={item.id}>{item.name}</option>)}</select><input value={row.exam.examTitle} onChange={(event)=>updateExam(row.id,{examTitle:event.target.value})} placeholder="시험명·범위"/><span><input inputMode="decimal" value={row.exam.score} onChange={(event)=>updateExam(row.id,{score:event.target.value})} placeholder="원점수"/><em>/</em><input inputMode="decimal" value={row.exam.maxScore} onChange={(event)=>updateExam(row.id,{maxScore:event.target.value})}/></span><input value={row.exam.evaluation} onChange={(event)=>updateExam(row.id,{evaluation:event.target.value})} placeholder="평가·피드백"/>{converted == null ? null : <small>환산 {converted}점</small>}</div>
        <div className="learning-homework previous"><p>{row.previousHomework || "지난 숙제 없음"}</p><select value={row.inspectionStatus} onChange={(event)=>update(row.id,{inspectionStatus:event.target.value})}>{homework.map(([value,label])=><option key={value} value={value}>{label}</option>)}</select><input value={row.inspectionNote} onChange={(event)=>update(row.id,{inspectionNote:event.target.value})} placeholder="검사 메모"/></div>
        <div className="learning-homework assigned"><textarea value={row.assignedHomework} onChange={(event)=>update(row.id,{assignedHomework:event.target.value})} placeholder="교재·페이지·문제 번호·제출일" rows={4}/></div>
      </article>;
    })}{!rows.length ? <p className="settings-empty">배정된 학생이 없습니다. 학생·시간 수정에서 학생을 추가해 주세요.</p> : null}</div>}</div></div>
    {error ? <p className="form-error learning-board-error">{error}</p> : null}
    <footer><span><b>{lessonState==="completed"?"수업 완료":"기록 중"}</b> · 완료 처리된 기록만 학부모 학습리포트에 반영됩니다.</span><span className="learning-completion-actions"><button type="button" className="secondary-button" disabled={saving==="all"||!rows.length} onClick={() => { if (lessonState==="completed"&&!confirm("수업 완료 기록을 취소할까요?\n입력 내용은 남고 학부모 리포트에서만 빠집니다.")) return; void save(false); }}>저장내용 취소</button><button type="button" className="primary" disabled={saving==="all"||!rows.length} onClick={() => void save(true)}>{saving==="all" ? "저장 중…" : "수업 완료"}</button></span></footer>
    {categoryManager ? <div className="modal-backdrop nested"><section role="dialog" aria-modal="true" aria-label="시험 종류 관리" className="student-modal exam-category-modal"><header><div><p className="eyebrow">개인별 시험</p><h2>시험 종류 관리</h2><span>선택 목록에 사용할 종류를 추가하거나 숨깁니다. 기존 기록은 삭제되지 않습니다.</span></div><button type="button" aria-label="닫기" onClick={() => setCategoryManager(false)}>×</button></header><div className="exam-category-add"><input value={newCategoryName} onChange={(event) => setNewCategoryName(event.target.value)} onKeyDown={(event) => { if (event.key === "Enter") void addCategory(); }} placeholder="예: 영단어, 중간고사" /><button type="button" className="primary" disabled={categorySaving} onClick={() => void addCategory()}>＋ 종류 추가</button></div><div className="exam-category-list">{categories.filter((item) => item.isActive).map((category) => <article key={category.id}><span><b>{category.name}</b><small>시험 입력 목록에 표시 중</small></span><button type="button" className="danger-button" disabled={categorySaving} onClick={() => void removeCategory(category)}>삭제</button></article>)}{!categories.some((item) => item.isActive) ? <p className="settings-empty">등록된 시험 종류가 없습니다.</p> : null}</div>{error ? <p className="form-error">{error}</p> : null}<footer><button type="button" className="secondary-button" onClick={() => setCategoryManager(false)}>닫기</button></footer></section></div> : null}
  </section>;
}

function SpecialFamilyReportReadStatus({supabase,sessionId}:{supabase:SupabaseClient;sessionId:string}) {
  const [data,setData]=useState<FamilyReadStatus|null>(null);
  const [open,setOpen]=useState(false);
  const [loading,setLoading]=useState(true);
  const load=useCallback(async()=>{setLoading(true);const{data:next,error}=await supabase.rpc("staff_special_lesson_family_report_read_status",{p_session_id:sessionId});setData(error?null:next as FamilyReadStatus);setLoading(false)},[sessionId,supabase]);
  useEffect(()=>{void load()},[load]);
  const confirmed=data?.confirmedStudents??0,unconfirmed=data?.unconfirmedStudents??0,unlinked=data?.unlinkedStudents??0;
  return <section className="family-read-status"><button type="button" className="family-read-summary" onClick={()=>setOpen(value=>!value)} disabled={loading}><span><small>학부모 학습리포트</small><b>{!data?.lessonId?"리포트 생성 전":`확인 ${confirmed}명 · 미확인 ${unconfirmed}명`}</b></span><span className="family-read-pills">{data?.lessonId?<em className="confirmed">확인 {confirmed}</em>:null}{data?.lessonId&&unconfirmed?<em className="unconfirmed">미확인 {unconfirmed}</em>:null}{unlinked?<em className="unlinked">학부모 미연결 {unlinked}</em>:null}<strong>{open?"접기":"학생별 보기"}</strong></span></button>{open&&data?<div className="family-read-details">{data.students.map((student)=><article key={student.studentId}><span><b>{student.studentName}</b><small>{[student.school,student.grade].filter(Boolean).join(" · ")||"학생 정보"}</small></span><span className={`family-read-state ${student.status}`}>{student.status==="confirmed"?"학부모 확인":student.status==="unconfirmed"?"미확인":"학부모 계정 미연결"}{student.status==="confirmed"&&student.viewedAt?<small>{formatReadTime(student.viewedAt)}</small>:null}</span></article>)}<footer><span>학부모 또는 보호자 한 명이라도 확인하면 ‘학부모 확인’으로 표시됩니다.</span><button type="button" onClick={()=>void load()}>새로고침</button></footer></div>:null}</section>;
}

function formatReadTime(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"numeric",day:"numeric",hour:"2-digit",minute:"2-digit",hour12:false}).format(new Date(value))}
