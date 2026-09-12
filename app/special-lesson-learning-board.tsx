"use client";

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import type { Profile } from "./supabase";
import { TeacherSpecialLessons } from "./teacher-special-lessons";
import type { SupabaseClient } from "@supabase/supabase-js";
import { StudentLearningHistory } from "./student-learning-history";
import { appConfirm } from "./app-dialog";
import { ExamCategoryModal, type ExamCategory } from "./class-learning-board";
import "./special-record-mobile.css";
import {editChanges,preservePendingEdits,mergeLiveEditValues,type EditValues} from "./class-record-concurrency";
import {specialInputValues,applySpecialValues} from "./special-record-edits";
import {compareEdits} from "./edit-conflict-dialog";

type Status = "present" | "late" | "absent";
type Exam = { examType: string; examTitle: string; score: string; maxScore: string; evaluation: string };
type Row = {
  id: string; name: string; school: string | null; grade: string | null;
  status: Status | null; lateMinutes: number | null; absenceReason: string | null;
  lessonContent: string; assignedHomework: string; previousHomework: string; inspectionStatus: string; inspectionNote: string; exam: Exam;
};
type AttendanceEditor = { row: Row; status: "late" | "absent"; value: string };
type Board = { notice: string; state: "draft" | "completed"; students: Array<Omit<Row, "exam"> & { exam?: Partial<Record<keyof Exam, string | number | null>> }> };
type Snapshot = {board:Board;values:EditValues;state:"draft"|"completed"};
type FamilyReadStudent = { studentId:string; studentName:string; school:string|null; grade:string|null; guardianCount:number; readCount:number; status:"confirmed"|"unconfirmed"|"unlinked"; viewedAt:string|null };
type FamilyReadStatus = { lessonId:string|null; totalStudents:number; linkedStudents:number; confirmedStudents:number; unconfirmedStudents:number; unlinkedStudents:number; students:FamilyReadStudent[] };

const attendance: [Status, string][] = [["present", "출석"], ["late", "지각"], ["absent", "결석"]];
const homework = [["", "미검사"], ["complete", "완료"], ["partial", "일부"], ["missing", "미제출"], ["excused", "면제"]];

export function SpecialLessonLearningBoard({ supabase, profile, sessionId, lessonKind, onClose, onAttendanceChange, embedded = false }: { supabase: SupabaseClient; profile: Profile; sessionId: string; lessonKind: "makeup"|"additional"; onClose: () => void; onAttendanceChange?: (change?:{studentId:string;status:Status|null}) => void | Promise<void>; embedded?: boolean }) {
  const [editingSchedule,setEditingSchedule]=useState(false);
  const [rows, setRows] = useState<Row[]>([]);
  const [notice, setNotice] = useState("");
  const [openStudentId, setOpenStudentId] = useState<string|null>(null);
  const [categories, setCategories] = useState<ExamCategory[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState("");
  const [error, setError] = useState("");
  const [categoryManager, setCategoryManager] = useState(false);
  const [lessonState, setLessonState] = useState<"draft" | "completed">("draft");
  const [historyStudent,setHistoryStudent]=useState<Row|null>(null);
  const [attendanceEditor,setAttendanceEditor]=useState<AttendanceEditor|null>(null);
  const baseline=useRef<Snapshot|null>(null);
  const busy=useRef(false);
  const latest=useRef({rows,notice});
  const scope=useRef(sessionId);
  const loadEpoch=useRef(0);
  useLayoutEffect(()=>{latest.current={rows,notice};scope.current=sessionId;},[rows,notice,sessionId]);
  const [reviewing,setReviewing]=useState(false);
  const [readRevision,setReadRevision]=useState(0);
  const load = useCallback(async (preserveInput=false) => {
    const epoch=++loadEpoch.current;
    setLoading(true);
    try {
    const [boardResponse, categoryResponse] = await Promise.all([
      supabase.rpc("staff_special_edit_snapshot", { p_session_id: sessionId }),
      supabase.rpc("staff_exam_categories"),
    ]);
    if(epoch!==loadEpoch.current||scope.current!==sessionId)return;
    if (boardResponse.error || categoryResponse.error) setError(boardResponse.error?.message ?? categoryResponse.error?.message ?? "수업 기록을 불러오지 못했습니다.");
    else {
      const snapshot=boardResponse.data as Snapshot;
      const board = snapshot.board;
      const old=baseline.current;
      const merge=preserveInput&&old?mergeLiveEditValues(old.values,specialInputValues(old.values,latest.current.rows,latest.current.notice),snapshot.values):{values:snapshot.values,baseline:snapshot.values};
      baseline.current={...snapshot,values:merge.baseline};
      setNotice(board?.notice ?? "");
      setLessonState(board?.state === "completed" ? "completed" : "draft");
      const nextRows=applySpecialValues(board.students.map(row=>({...row,exam:{examType:"",examTitle:"",score:"",maxScore:"100",evaluation:""}})),merge.values);
      nextRows.push(...latest.current.rows.filter(row=>!nextRows.some(next=>next.id===row.id)&&Boolean(merge.values.students[row.id])));
      latest.current={rows:nextRows,notice:merge.values.notice};setRows(nextRows);setNotice(merge.values.notice);
      setCategories((categoryResponse.data ?? []) as ExamCategory[]);
      setError("");
    }
    }catch(e){setError(e instanceof Error?e.message:"수업을 불러오지 못했습니다.");}finally{if(epoch===loadEpoch.current)setLoading(false);}
  }, [sessionId, supabase]);
  useEffect(() => {baseline.current=null;void load();return()=>{loadEpoch.current++;};}, [load]);
  useEffect(() => {
    const closeTopLayer = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      if (editingSchedule) return;
      if (attendanceEditor) setAttendanceEditor(null);
      else if (categoryManager) setCategoryManager(false);
      else onClose();
    };
    document.addEventListener("keydown", closeTopLayer);
    return () => document.removeEventListener("keydown", closeTopLayer);
  }, [attendanceEditor, categoryManager, onClose, editingSchedule]);
  const refreshCategories = async () => {
    const { data, error: categoryError } = await supabase.rpc("staff_exam_categories");
    if (categoryError) setError(categoryError.message);
    else setCategories((data ?? []) as ExamCategory[]);
  };
  const update = (id: string, patch: Partial<Row>) => setRows((current) => current.map((row) => row.id === id ? { ...row, ...patch } : row));
  const updateExam = (id: string, patch: Partial<Exam>) => setRows((current) => current.map((row) => row.id === id ? { ...row, exam: { ...row.exam, ...patch } } : row));
  const acceptSnapshot=(snapshot:Snapshot,submitted:EditValues)=>{
    const current=specialInputValues(submitted,latest.current.rows,latest.current.notice);
    const values=preservePendingEdits(current,submitted,snapshot.values);
    baseline.current=snapshot;
    const nextRows=applySpecialValues(snapshot.board.students.map(row=>({...row,exam:{examType:"",examTitle:"",score:"",maxScore:"100",evaluation:""}})),values);
    latest.current={rows:nextRows,notice:values.notice};setRows(nextRows);setNotice(values.notice);setLessonState(snapshot.state);setReadRevision(n=>n+1);
  };
  const persistAttendance = async (row: Row, status: Status | null, late: number | null, reason: string | null) => {
    const base=baseline.current;if(!base||busy.current)return false;
    busy.current=true;setSaving(row.id);setError("");
    try{
      const values=structuredClone(base.values),v=values.students[row.id];if(!v)throw new Error("명단이 변경됐습니다. 최신 내용을 비교해 주세요.");
      v.status=status;v.lateMinutes=late;v.absenceReason=reason??"";
      const {data,error:saveError}=await supabase.rpc("staff_patch_special_record",{p_session_id:sessionId,p_changes:editChanges(base.values,values),p_expected_state:base.state,p_mode:"attendance"});
      if(saveError)throw new Error(saveError.message);
      if(scope.current!==sessionId)return false;
      acceptSnapshot(data as Snapshot,values);await onAttendanceChange?.({studentId:row.id,status});return true;
    }catch(e){setError(e instanceof Error?e.message:"출결을 저장하지 못했습니다.");return false;}finally{busy.current=false;setSaving("");}
  };
  const reviewLatest=async()=>{
    const base=baseline.current;if(!base||busy.current)return;
    busy.current=true;setReviewing(true);
    try{
      const {data,error:readError}=await supabase.rpc("staff_special_edit_snapshot",{p_session_id:sessionId});if(readError)throw new Error(readError.message);
      if(scope.current!==sessionId)return;
      const remote=data as Snapshot,local=specialInputValues(base.values,latest.current.rows,latest.current.notice);
      const changes=editChanges(base.values,local);
      if(changes.some(c=>c.path.length===3&&!remote.values.students[c.path[1]])){setError("명단에서 빠진 학생의 입력이 있습니다. 내용을 복사한 뒤 수업을 다시 열어 주세요.");return;}
      const label:Record<string,string>={notice:"안내",lessonContent:"수업 내용",assignedHomework:"숙제",inspectionStatus:"검사 상태",inspectionNote:"검사 메모",exam_examType:"시험 종류",exam_examTitle:"시험명",exam_score:"점수",exam_maxScore:"만점",exam_evaluation:"평가"};
      const value=(v:EditValues,path:string[])=>path.length===1?v.notice:v.students[path[1]][path[2]];
      const conflicts=changes.filter(c=>c.path[2]!=="exam_id"&&value(remote.values,c.path)!==c.before&&value(remote.values,c.path)!==c.value);
      const choices=conflicts.length?await compareEdits(conflicts.map(c=>({id:c.path.join('/'),student:rows.find(r=>r.id===c.path[1])?.name??"공통",field:label[c.path.at(-1)!]??"수업 기록",mine:String(c.value??""),latest:String(value(remote.values,c.path)??"")}))):{};
      if(choices===null||scope.current!==sessionId)return;
      const merged=preservePendingEdits(local,base.values,remote.values);
      for(const c of conflicts)if(choices[c.path.join('/')]==='latest'){if(c.path.length===1)merged.notice=remote.values.notice;else merged.students[c.path[1]][c.path[2]]=value(remote.values,c.path);}
      const nextRows=applySpecialValues(remote.board.students.map(row=>({...row,exam:{examType:"",examTitle:"",score:"",maxScore:"100",evaluation:""}})),merged);
      baseline.current=remote;latest.current={rows:nextRows,notice:merged.notice};setRows(nextRows);setNotice(merged.notice);setLessonState(remote.state);setError("");
    }catch(e){setError(e instanceof Error?e.message:"최신 내용을 확인하지 못했습니다.");}finally{busy.current=false;setReviewing(false);}
  };
  const saveAttendance = async (row: Row, status: Status) => {
    const next = row.status === status ? null : status;
    if (next === "late") { setAttendanceEditor({ row, status: "late", value: String(row.lateMinutes ?? 10) }); return; }
    if (next === "absent") { setAttendanceEditor({ row, status: "absent", value: row.absenceReason ?? "" }); return; }
    await persistAttendance(row, next, null, null);
  };
  const saveAttendanceDetail = async () => {
    if (!attendanceEditor) return;
    const { row, status, value } = attendanceEditor;
    const late = status === "late" ? Number(value) : null;
    const reason = status === "absent" ? value.trim() : null;
    if (status === "late" && (!Number.isFinite(late) || late == null || late < 1)) return setError("지각 시간을 숫자로 입력해 주세요.");
    if (status === "absent" && !reason) return setError("결석 사유를 입력해 주세요.");
    if (await persistAttendance(row, status, late, reason)) setAttendanceEditor(null);
  };
  const save = async (complete: boolean) => {
    if (complete) { const missing = rows.filter((row) => !row.status).map((row) => row.name); if (missing.length) return setError(`출결 미입력 학생: ${missing.join(", ")}`); }
    for (const row of rows) { const hasExamInput=Boolean(row.exam.examTitle.trim()||row.exam.score!==""||row.exam.evaluation.trim()); if(hasExamInput&&!row.exam.examType.trim())return setError(`${row.name} 학생의 시험 종류를 선택해 주세요.`); const score = Number(row.exam.score), max = Number(row.exam.maxScore); if (row.exam.score !== "" && (!Number.isFinite(score) || !Number.isFinite(max) || max <= 0 || score < 0 || score > max)) return setError(`${row.name} 학생의 점수를 확인해 주세요.`); }
    const base=baseline.current;if(!base||busy.current)return;
    busy.current=true;setSaving("all");setError("");
    try{
      const submitted=specialInputValues(base.values,rows,notice);
      const {data,error:saveError}=await supabase.rpc("staff_patch_special_record",{p_session_id:sessionId,p_changes:editChanges(base.values,submitted),p_expected_state:base.state,p_mode:complete?"completed":"draft"});
      if(saveError)throw new Error(saveError.message);
      if(scope.current===sessionId)acceptSnapshot(data as Snapshot,submitted);
    }catch(e){setError(e instanceof Error?e.message:"저장하지 못했습니다.");}finally{busy.current=false;setSaving("");}
  };
  const deleteRecord = async () => {
    if (!await appConfirm({eyebrow:"수업 기록 삭제",title:"이 보강·추가수업 기록을 삭제할까요?",notice:"출결·수업 내용·시험·숙제와 학부모 리포트 반영이 모두 삭제됩니다.",confirmLabel:"기록 삭제",tone:"danger"})) return;
    setSaving("all"); setError("");
    const { error: deleteError } = await supabase.rpc("staff_delete_special_lesson_record", { p_session_id: sessionId });
    if (deleteError) setError(deleteError.message);
    else { setLessonState("draft"); await Promise.all([load(), onAttendanceChange?.()]); }
    setSaving("");
  };
  return <section inert={editingSchedule||reviewing} className={`${embedded ? "class-learning-board special-board-embedded" : "student-modal"} special-board-modal special-record-viewport`} spellCheck={false}>
    <SpecialFamilyReportReadStatus key={readRevision} supabase={supabase} sessionId={sessionId} />
    <div className="learning-board-scroll"><div className="learning-board-table"><div className="learning-board-heading"><span>학생·출결</span><span>개인별 수업 내용</span><span className="learning-exam-heading"><b>개인별 시험</b><button type="button" onClick={() => setCategoryManager(true)}>시험 카테고리 관리</button></span><span>지난 숙제 검사</span><span>오늘 내줄 숙제</span></div>
    {loading ? <p className="settings-empty">불러오는 중이에요…</p> : <div className="learning-board-rows">{rows.map((row) => {
      const score = Number(row.exam.score), max = Number(row.exam.maxScore), converted = row.exam.score !== "" && max > 0 ? Math.round(score / max * 1000) / 10 : null;
      const detailCount=[row.lessonContent.trim(),row.exam.examType.trim()||row.exam.examTitle.trim(),row.inspectionStatus.trim()||row.assignedHomework.trim()].filter(Boolean).length;
      return <article key={row.id} className={`${openStudentId===row.id?"mobile-open":""} ${row.status&&detailCount===3?"record-ready":"record-pending"}`}>
        <div className="mobile-student-record-head"><button type="button" className="mobile-student-record-toggle" aria-expanded={openStudentId===row.id} onClick={()=>setOpenStudentId(current=>current===row.id?null:row.id)}><i>{row.name[0]}</i><span><b>{row.name}</b><small>{[row.school,row.grade].filter(Boolean).join(" · ")}</small></span><em>{detailCount}/3 입력</em><strong aria-hidden="true">⌄</strong></button><button type="button" className="mobile-student-history" aria-label={`${row.name} 학생 누적 기록 보기`} onClick={()=>setHistoryStudent(row)}>기록</button></div>
        <div className="learning-person-attendance"><span className="learning-student"><button type="button" className="learning-student-history-button" onClick={()=>setHistoryStudent(row)} title={`${row.name} 학생 누적 수업 기록 보기`}><i>{row.name[0]}</i><b>{row.name}</b><small>{[row.school,row.grade].filter(Boolean).join(" · ")}</small></button></span><div className="learning-attendance">{attendance.map(([status,label]) => <button type="button" key={status} className={`${status} ${row.status === status ? "active" : ""}`} disabled={saving===row.id} onClick={() => void saveAttendance(row,status)}>{label}</button>)}{row.status ? <small>{row.status === "late" ? `${row.lateMinutes}분 지각 · ` : row.status === "absent" && row.absenceReason ? `${row.absenceReason} · ` : ""}같은 버튼을 다시 누르면 취소</small> : null}</div></div>
        <div className="learning-individual-content"><textarea value={row.lessonContent} onChange={(event) => update(row.id,{lessonContent:event.target.value})} placeholder="이 학생의 교재·단원·진도" rows={4}/></div>
        <div className="learning-exam individual"><select value={row.exam.examType} onChange={(event) => updateExam(row.id,{examType:event.target.value})}><option value="">종류 선택</option>{categories.filter((item)=>item.isActive).map((item)=><option key={item.id}>{item.name}</option>)}</select><input value={row.exam.examTitle} onChange={(event)=>updateExam(row.id,{examTitle:event.target.value})} placeholder="시험명·범위"/><span><input inputMode="decimal" value={row.exam.score} onChange={(event)=>updateExam(row.id,{score:event.target.value})} placeholder="원점수"/><em>/</em><input inputMode="decimal" value={row.exam.maxScore} onChange={(event)=>updateExam(row.id,{maxScore:event.target.value})}/></span><input value={row.exam.evaluation} onChange={(event)=>updateExam(row.id,{evaluation:event.target.value})} placeholder="평가·피드백"/>{converted == null ? null : <small>환산 {converted}점</small>}</div>
        <div className="learning-homework previous"><p>{row.previousHomework || "지난 숙제 없음"}</p><select value={row.inspectionStatus} onChange={(event)=>update(row.id,{inspectionStatus:event.target.value})}>{homework.map(([value,label])=><option key={value} value={value}>{label}</option>)}</select><input value={row.inspectionNote} onChange={(event)=>update(row.id,{inspectionNote:event.target.value})} placeholder="검사 메모"/></div>
        <div className="learning-homework assigned"><textarea value={row.assignedHomework} onChange={(event)=>update(row.id,{assignedHomework:event.target.value})} placeholder="교재·페이지·문제 번호·제출일" rows={4}/></div>
      </article>;
    })}{!rows.length ? <p className="settings-empty">배정된 학생이 없습니다. 학생·시간 수정에서 학생을 추가해 주세요.</p> : null}</div>}</div></div>
    {error ? <div className="form-error learning-board-error">{error}{/수정|완료 상태|명단/.test(error)&&<button type="button" className="secondary-button" disabled={reviewing} onClick={()=>void reviewLatest()}>{reviewing?"확인 중…":"최신 내용 비교"}</button>}</div> : null}
    <footer><span><b>{lessonState==="completed"?"수업 완료":"기록 중"}</b> · 완료 처리된 기록만 학부모 학습리포트에 반영됩니다.</span><span className="learning-completion-actions"><button type="button" className="secondary-button" disabled={Boolean(saving)||loading} onClick={()=>setEditingSchedule(true)}>일정 수정</button>{lessonState==="completed"?<><button type="button" className="danger-button" disabled={saving==="all"||!rows.length} onClick={()=>void deleteRecord()}>기록 삭제</button><button type="button" className="primary" disabled={saving==="all"||!rows.length} onClick={()=>void save(true)}>{saving==="all"?"저장 중…":"수정 저장"}</button></>:<><button type="button" className="secondary-button" disabled={saving==="all"||!rows.length} onClick={()=>void save(false)}>임시저장</button><button type="button" className="primary" disabled={saving==="all"||!rows.length} onClick={()=>void save(true)}>{saving==="all"?"저장 중…":"수업 완료"}</button></>}</span></footer>
    {editingSchedule&&typeof document!=="undefined"&&createPortal(<TeacherSpecialLessons supabase={supabase} profile={profile} editorSessionId={sessionId} onEditorClose={()=>setEditingSchedule(false)} onEditorDeleted={async()=>{setEditingSchedule(false);onClose();await onAttendanceChange?.();}} onEditorSaved={async()=>{setEditingSchedule(false);await load(true);await onAttendanceChange?.();}}/>,document.body)}
    {attendanceEditor?<div className="modal-backdrop nested attendance-editor-backdrop" onMouseDown={event=>{if(event.target===event.currentTarget)setAttendanceEditor(null)}}><form className="attendance-editor-modal" role="dialog" aria-modal="true" aria-labelledby="special-attendance-editor-title" onSubmit={event=>{event.preventDefault();void saveAttendanceDetail()}}><header><span className={`attendance-editor-icon ${attendanceEditor.status}`}>{attendanceEditor.status==="late"?"분":"!"}</span><div><small>{attendanceEditor.status==="late"?"지각 시간 기록":"결석 사유 기록"}</small><h2 id="special-attendance-editor-title">{attendanceEditor.row.name} 학생</h2></div><button type="button" aria-label="닫기" onClick={()=>setAttendanceEditor(null)}>×</button></header><label><b>{attendanceEditor.status==="late"?"몇 분 지각했나요?":"결석 사유를 입력해 주세요"}</b>{attendanceEditor.status==="late"?<div className="attendance-minute-input"><input autoFocus type="number" min="1" inputMode="numeric" value={attendanceEditor.value} onChange={event=>setAttendanceEditor(current=>current?{...current,value:event.target.value}:current)}/><span>분</span></div>:<textarea autoFocus rows={3} value={attendanceEditor.value} onChange={event=>setAttendanceEditor(current=>current?{...current,value:event.target.value}:current)} placeholder="예: 병원 진료, 개인 사정"/>}</label><footer><button type="button" className="secondary-button" onClick={()=>setAttendanceEditor(null)}>취소</button><button type="submit" className="primary" disabled={saving===attendanceEditor.row.id}>{saving===attendanceEditor.row.id?"저장 중…":"기록하기"}</button></footer></form></div>:null}
    {categoryManager ? <ExamCategoryModal supabase={supabase} categories={categories} onClose={() => setCategoryManager(false)} onChanged={refreshCategories} /> : null}
    {historyStudent?<div className="modal-backdrop nested" onMouseDown={event=>{if(event.target===event.currentTarget)setHistoryStudent(null)}}><section className="student-modal student-learning-history-modal" role="dialog" aria-modal="true"><header><div><p className="eyebrow">교직원 전용 · 누적 수업 기록</p><h2>{historyStudent.name}<small className="history-type-label">{lessonKind==="makeup"?"보강수업 기록":"추가수업 기록"}</small></h2><span>{[historyStudent.school,historyStudent.grade].filter(Boolean).join(" · ")||"학생 기록"}</span></div><button type="button" aria-label="닫기" onClick={()=>setHistoryStudent(null)}>×</button></header><StudentLearningHistory supabase={supabase} studentId={historyStudent.id} initialSource={lessonKind}/></section></div>:null}
  </section>;
}

function SpecialFamilyReportReadStatus({supabase,sessionId}:{supabase:SupabaseClient;sessionId:string}) {
  const [data,setData]=useState<FamilyReadStatus|null>(null);
  const [open,setOpen]=useState(false);
  const [loading,setLoading]=useState(true);
  const load=useCallback(async()=>{setLoading(true);const{data:next,error}=await supabase.rpc("staff_special_lesson_family_report_read_status",{p_session_id:sessionId});setData(error?null:next as FamilyReadStatus);setLoading(false)},[sessionId,supabase]);
  useEffect(()=>{void load()},[load]);
  const confirmed=data?.confirmedStudents??0,unconfirmed=data?.unconfirmedStudents??0,unlinked=data?.unlinkedStudents??0,connected=confirmed+unconfirmed;
  return <section className="family-read-status"><button type="button" className="family-read-summary" onClick={()=>setOpen(value=>!value)} disabled={loading}><span><small>학부모 확인 현황</small><b>{!data?.lessonId?"리포트 생성 전":`확인 ${confirmed} / ${connected}명`}</b></span><span className="family-read-pills">{unlinked?<em className="unlinked">미연결 {unlinked}명</em>:null}<strong>{open?"접기":"학생별 보기"}</strong></span></button>{open&&data?<div className="family-read-details">{data.students.map((student)=><article key={student.studentId}><span><b>{student.studentName}</b><small>{[student.school,student.grade].filter(Boolean).join(" · ")||"학생 정보"}</small></span><span className={`family-read-state ${student.status}`}>{student.status==="confirmed"?"학부모 확인":student.status==="unconfirmed"?"미확인":"학부모 계정 미연결"}{student.status==="confirmed"&&student.viewedAt?<small>{formatReadTime(student.viewedAt)}</small>:null}</span></article>)}<footer><span>학부모 또는 보호자 한 명이라도 확인하면 ‘학부모 확인’으로 표시됩니다.</span><button type="button" onClick={()=>void load()}>새로고침</button></footer></div>:null}</section>;
}

function formatReadTime(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"numeric",day:"numeric",hour:"2-digit",minute:"2-digit",hour12:false}).format(new Date(value))}
