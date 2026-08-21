"use client";

import type { FormEvent } from "react";
import { useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { StudentLifecyclePanel } from "./student-lifecycle-panel";
import { StudentRelevantTimetable, type WeeklyTimetableRow } from "./weekly-timetable";

type StudentValues = {
  id: string;
  name: string;
  school: string;
  grade: string;
  phone: string;
  residence: string;
  pickupLocation: string;
  dropoffLocation: string;
  status: string;
  internalNote: string;
  guardianName?: string;
  guardianPhone?: string;
};
type RosterStudent = {
  id: string;
  name: string;
  school: string | null;
  grade: string | null;
  status: string;
  enrollments: unknown[];
};
type Summary = {
  attendanceTotal: number;
  present: number;
  late: number;
  absent: number;
  assignmentOpen: number;
  upcomingMakeups: number;
  lastConsultedAt: string | null;
};
type ClassItem = {
  id: string;
  name: string;
  subject: string;
  room: string | null;
  status: string;
  startedOn: string;
  teachers: string;
  color?: string;
};
type AttendanceItem = {
  id: string;
  lessonDate: string;
  className: string;
  status: "present" | "late" | "absent" | "excused";
  note: string | null;
};
type MakeupItem = {
  id: string;
  className: string;
  missedDate: string;
  scheduledAt: string;
  endsAt: string;
  room: string;
  status: string;
  teacherName: string;
  note: string | null;
  recordKind?: "absence_makeup" | "individual_makeup" | "additional";
};
type AssignmentItem = {
  id: string;
  title: string;
  className: string;
  dueAt: string;
  status: string;
  feedback: string | null;
};
type ConsultationItem = {
  id: string;
  consultedAt: string;
  type: string;
  consultantName: string;
  internalNote: string | null;
  nextContactOn: string | null;
};
type Guardian = {
  id: string;
  name: string;
  phone: string;
  relationship: string | null;
  isPrimary: boolean;
};
type ExamProgressItem = {
  id: string;
  lessonDate: string;
  className: string;
  subject: string;
  examType: string;
  examTitle: string;
  score: number | null;
  maxScore: number;
  percent: number | null;
  evaluation: string;
  source: "regular" | "correction" | "makeup" | "additional";
};
type AttendanceSummary = { attendanceTotal: number; present: number; late: number; absent: number };
type CorrectionAttendanceItem = AttendanceItem & { subject: string; startTime: string };
type CorrectionLearningItem = { id:string; lessonDate:string; subject:string; homeworkInstruction:string; homeworkStatus:string; homeworkNote:string; correctionContent:string; assistantFeedback:string };
type DetailInsights = {
  regularAttendance: AttendanceSummary;
  correctionAttendance: AttendanceSummary;
  correctionAttendanceRecords: CorrectionAttendanceItem[];
  correctionExams: Omit<ExamProgressItem,"source">[];
  correctionLearning: CorrectionLearningItem[];
};
type SpecialInsights = { attendance:AttendanceSummary; upcomingMakeups:number; exams:Omit<ExamProgressItem,"source">[] };
type DetailData = {
  summary: Summary;
  classes: ClassItem[];
  guardians: Guardian[];
  attendance: AttendanceItem[];
  makeups: MakeupItem[];
  assignments: AssignmentItem[];
  consultations: ConsultationItem[];
  timetable: WeeklyTimetableRow[];
  examProgress: ExamProgressItem[];
  insights: DetailInsights;
  special: SpecialInsights;
};
type AttendanceHistory = {
  regularAttendance: AttendanceItem[];
  correctionAttendance: CorrectionAttendanceItem[];
  makeups: MakeupItem[];
};
type Tab = "summary" | "profile" | "classes" | "attendance" | "learning";
const statusLabels = {
  present: "출석",
  late: "지각",
  absent: "결석",
  excused: "결석",
};
const consultationLabels: Record<string, string> = {
  student: "학생",
  guardian: "학부모",
  phone: "전화",
  academic: "학습",
  other: "기타",
};

export function StudentDetailHub({ supabase, student, rosterStudent, timetable, onClose, onUpdate, onDelete, onAssign, onLifecycleUpdated }: { supabase: SupabaseClient; student: StudentValues; rosterStudent?: RosterStudent; timetable: WeeklyTimetableRow[]; onClose: () => void; onUpdate: (values: StudentValues) => Promise<void>; onDelete: (student: StudentValues) => Promise<void>; onAssign: (student: RosterStudent) => void; onLifecycleUpdated: (status: string) => void }) {
  const [tab, setTab] = useState<Tab>("summary");
  const [data, setData] = useState<DetailData | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState("");
  const [values, setValues] = useState(student);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [deleteName, setDeleteName] = useState("");
  useEffect(() => {
    let active = true;
    void Promise.all([
      supabase.rpc("staff_student_detail_hub", { p_student_id: student.id }),
      supabase.rpc("staff_student_exam_progress", { p_student_id: student.id }),
      supabase.rpc("staff_student_detail_insights", { p_student_id: student.id }),
      supabase.rpc("staff_student_attendance_makeup_history", { p_student_id: student.id }),
      supabase.rpc("staff_student_special_lesson_insights", { p_student_id: student.id }),
    ]).then(([detailResult, examResult, insightResult, historyResult, specialResult]) => {
      if (!active) return;
      if (detailResult.error || examResult.error || insightResult.error || historyResult.error || specialResult.error) setLoadError("학생 통합 기록을 불러오지 못했습니다.");
      else {
        const detail = detailResult.data as Omit<DetailData, "timetable" | "examProgress" | "insights">;
        const insights = insightResult.data as DetailInsights;
        const history = historyResult.data as AttendanceHistory;
        const special = specialResult.data as SpecialInsights;
        const colors = new Map(timetable.map((row) => [row.className, row.color]));
        const primaryGuardian=detail.guardians.find((item)=>item.isPrimary)??detail.guardians[0];
        setValues((current)=>({...current,guardianName:primaryGuardian?.name??"",guardianPhone:primaryGuardian?.phone??""}));
        setData({
          ...detail,
          attendance: history.regularAttendance ?? [],
          makeups: history.makeups ?? [],
          classes: detail.classes.map((item) => ({
            ...item,
            color: colors.get(item.name),
          })),
          timetable,
          examProgress: [
            ...((examResult.data ?? []) as Omit<ExamProgressItem,"source">[]).map((item)=>({...item,source:"regular" as const})),
            ...(insights.correctionExams??[]).map((item)=>({...item,source:"correction" as const})),
            ...(special.exams??[]).map((item)=>({...item,source:(item.className==="개별 보강"?"makeup":"additional") as "makeup"|"additional"})),
          ],
          insights: { ...insights, correctionAttendanceRecords: history.correctionAttendance ?? [] },
          special,
        });
      }
      setLoading(false);
    });
    return () => {
      active = false;
    };
  }, [student.id, supabase, timetable]);
  const update = (field: keyof Omit<StudentValues, "id">, value: string) => setValues((current) => ({ ...current, [field]: value }));
  const submit = async (event: FormEvent) => {
    event.preventDefault();
    setSubmitting(true);
    setError("");
    try {
      await onUpdate(values);
    } catch {
      setError("학생 정보를 수정하지 못했습니다.");
      setSubmitting(false);
    }
  };
  const remove = async () => {
    setSubmitting(true);
    setError("");
    try {
      await onDelete(student);
    } catch {
      setError("학생을 삭제하지 못했습니다.");
      setSubmitting(false);
    }
  };
  return (
    <div
      className="modal-backdrop"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <section className="student-modal student-hub-modal" role="dialog" aria-modal="true">
        <header>
          <div>
            <p className="eyebrow">학생 통합 관리</p>
            <h2>{student.name}</h2>
            <span>
              {student.school || "학교 미입력"}
              {student.grade ? ` · ${student.grade}` : ""} · {studentStatus(student.status)}
            </span>
          </div>
          <button type="button" aria-label="닫기" onClick={onClose}>
            ×
          </button>
        </header>
        <nav className="student-hub-tabs">
          {(
            [
              ["summary", "요약"],
              ["profile", "기본정보"],
              ["classes", "수강 클래스"],
              ["attendance", "출결·보강"],
              ["learning", "학습·상담"],
            ] as [Tab, string][]
          ).map(([id, label]) => (
            <button key={id} className={tab === id ? "active" : ""} onClick={() => setTab(id)}>
              {label}
            </button>
          ))}
        </nav>
        <div className="student-hub-body">
          {loading && <p className="hub-message">학생 기록을 불러오는 중이에요…</p>}
          {loadError && <p className="hub-message error">{loadError}</p>}
          {data && tab === "summary" && <SummaryTab data={data} />}{" "}
          {tab === "profile" && (
            <div className="student-profile-settings">
              <form className="student-profile-form" onSubmit={submit}>
                <section className="student-profile-card">
                  <header><div><h3>학생 기본정보</h3><p>학생의 학교 정보와 연락처를 관리합니다.</p></div></header>
                  <div className="form-grid">
                    <label>
                    학생 이름 <b>*</b>
                    <input required value={values.name} onChange={(event) => update("name", event.target.value)} />
                    </label>
                    <label>
                    학교
                    <input value={values.school} onChange={(event) => update("school", event.target.value)} />
                    </label>
                    <label>
                    학년
                    <input value={values.grade} onChange={(event) => update("grade", event.target.value)} />
                    </label>
                    <label>
                    학생 연락처
                    <input value={values.phone} onChange={(event) => update("phone", event.target.value)} />
                    </label>
                    <label>
                    학부모 성함
                    <input value={values.guardianName??""} onChange={(event)=>update("guardianName",event.target.value)} placeholder="예: 김보호" />
                    </label>
                    <label>
                    학부모 연락처
                    <input type="tel" inputMode="numeric" value={values.guardianPhone??""} onChange={(event)=>update("guardianPhone",event.target.value)} placeholder="숫자만 입력" />
                    </label>
                  </div>
                </section>
                <section className="student-profile-card">
                  <header><div><h3>학원 이용정보</h3><p>거주지, 차량 이용 위치와 내부 메모를 관리합니다.</p></div></header>
                  <div className="form-grid">
                    <label className="full">
                    거주지
                    <input value={values.residence} onChange={(event) => update("residence", event.target.value)} placeholder="예: 배곧동 한라비발디" />
                    </label>
                    <label>
                    차량 승차 위치
                    <input value={values.pickupLocation} onChange={(event) => update("pickupLocation", event.target.value)} placeholder="예: 아파트 정문" />
                    </label>
                    <label>
                    차량 하차 위치
                    <input value={values.dropoffLocation} onChange={(event) => update("dropoffLocation", event.target.value)} placeholder="예: 아파트 후문" />
                    </label>
                    <label className="full">
                    내부 메모
                    <textarea rows={3} value={values.internalNote} onChange={(event) => update("internalNote", event.target.value)} />
                    </label>
                  </div>
                </section>
                {error&&<p className="form-error">{error}</p>}
                <footer className="student-profile-savebar"><span>변경한 기본정보를 저장합니다.</span><div>
                  <button type="button" className="secondary-button" onClick={onClose}>
                    취소
                  </button>
                  <button className="primary" disabled={submitting}>
                    {submitting ? "저장 중…" : "기본정보 저장"}
                  </button>
                </div></footer>
                <section className="student-danger-zone"><div><b>학생 삭제</b><small>학생과 연결된 모든 기록이 영구적으로 삭제됩니다.</small></div><button type="button" className="danger-link" onClick={()=>setConfirmDelete((current)=>!current)}>{confirmDelete?"삭제 취소":"삭제하기"}</button>{confirmDelete&&<div className="delete-confirm"><b>연결된 모든 기록도 함께 삭제됩니다.</b><span>확인을 위해 <strong>{student.name}</strong>을 입력하세요.</span><input value={deleteName} onChange={(event)=>setDeleteName(event.target.value)} placeholder={student.name}/><button type="button" disabled={submitting||deleteName!==student.name} onClick={()=>void remove()}>영구 삭제</button></div>}</section>
              </form>
              <StudentLifecyclePanel
                supabase={supabase}
                studentId={student.id}
                status={values.status}
                onChanged={(status) => {
                  setValues((current) => ({ ...current, status }));
                  onLifecycleUpdated(status);
                }}
              />
            </div>
          )}
          {data && tab === "classes" && <ClassesTab classes={data.classes} onAssign={rosterStudent ? () => onAssign(rosterStudent) : undefined} />} {data && tab === "attendance" && <AttendanceTab attendance={data.attendance} correctionAttendance={data.insights.correctionAttendanceRecords} makeups={data.makeups} />} {data && tab === "learning" && <LearningTab assignments={data.assignments} corrections={data.insights.correctionLearning} consultations={data.consultations} />}
        </div>
      </section>
    </div>
  );
}

function SummaryTab({ data }: { data: DetailData }) {
  const regularRate = attendanceRate(data.insights.regularAttendance);
  const correctionRate = attendanceRate(data.insights.correctionAttendance);
  const specialRate = attendanceRate(data.special.attendance);
  return (
    <>
      <div className="student-summary-cards">
        <article>
          <span>정규수업 출석률 · 30일</span>
          <b>{regularRate === null ? "-" : `${regularRate}%`}</b>
          <small>출석 {data.insights.regularAttendance.present} · 지각 {data.insights.regularAttendance.late} · 결석 {data.insights.regularAttendance.absent}</small>
        </article>
        <article>
          <span>첨삭수업 출석률 · 30일</span>
          <b>{correctionRate === null ? "-" : `${correctionRate}%`}</b>
          <small>출석 {data.insights.correctionAttendance.present} · 지각 {data.insights.correctionAttendance.late} · 결석 {data.insights.correctionAttendance.absent}</small>
        </article>
        <article><span>보강·추가수업 출석률 · 30일</span><b>{specialRate===null?"-":`${specialRate}%`}</b><small>출석 {data.special.attendance.present} · 지각 {data.special.attendance.late} · 결석 {data.special.attendance.absent}</small></article>
        <article>
          <span>미완료 정규 과제</span>
          <b>{data.summary.assignmentOpen}</b>
          <small>제출 전·첨삭 대기</small>
        </article>
        <article>
          <span>예정 보강</span>
          <b>{data.summary.upcomingMakeups+data.special.upcomingMakeups}</b>
          <small>{data.summary.lastConsultedAt?`최근 상담 ${formatDate(data.summary.lastConsultedAt)}`:"최근 상담 없음"}</small>
        </article>
      </div>
      <StudentExamTrend items={data.examProgress} />
      <section className="student-personal-schedule">
        <header>
          <h3>개인 수업 시간표</h3>
          <p>현재 수업이 있는 요일과 시간만 표시합니다.</p>
        </header>
        <StudentRelevantTimetable rows={data.timetable} />
      </section>
    </>
  );
}

function StudentExamTrend({ items }: { items: ExamProgressItem[] }) {
  const sourceOptions:ExamSourceFilter[]=["all","regular","correction","makeup","additional"];
  const[source,setSource]=useState<ExamSourceFilter>("all");
  const sourceItems=items.filter(item=>(source==="all"||item.source===source)&&item.percent!==null);
  const subjects=Array.from(new Set(sourceItems.map(item=>item.subject).filter(Boolean)));
  const[subject,setSubject]=useState("");
  const[range,setRange]=useState<"week"|"month"|"quarter"|"all">("month");
  const selectedSubject=subject&&subjects.includes(subject)?subject:(subjects[0]??"");
  const allScored=sourceItems.filter(item=>item.subject===selectedSubject);
  const rangeDays=range==="week"?7:range==="month"?30:range==="quarter"?90:null;
  const cutoffDate=new Date();
  cutoffDate.setHours(0,0,0,0);
  if(rangeDays!==null) cutoffDate.setDate(cutoffDate.getDate()-(rangeDays-1));
  const scored=rangeDays===null?allScored:allScored.filter(item=>{
    const lessonTime=new Date(`${item.lessonDate}T00:00:00`).getTime();
    return Number.isFinite(lessonTime)&&lessonTime>=cutoffDate.getTime();
  });
  const recent=scored.slice(-3);
  const average=recent.length?Math.round(recent.reduce((sum,item)=>sum+(item.percent??0),0)/recent.length*10)/10:null;
  const latest=scored.at(-1)?.percent??null;
  const previous=scored.at(-2)?.percent??null;
  const delta=latest!==null&&previous!==null?Math.round((latest-previous)*10)/10:null;
  return (
    <section className="student-exam-progress">
      <header>
        <div>
          <h3>시험 성적 추이</h3>
          <p>수업 종류와 과목, 조회 기간을 선택해 시험의 100점 환산 점수를 비교합니다.</p>
        </div>
        <div className="student-exam-selects">
          <label>
            수업 구분
            <select value={source} onChange={(event)=>{setSource(event.target.value as ExamSourceFilter);setSubject("")}}>
              {sourceOptions.map(value=><option key={value} value={value}>{sourceLabel(value)}</option>)}
            </select>
          </label>
          <label>
            조회 기간
            <select value={range} onChange={(event)=>setRange(event.target.value as "week"|"month"|"quarter"|"all")}>
              <option value="week">최근 7일</option>
              <option value="month">최근 30일</option>
              <option value="quarter">최근 90일</option>
              <option value="all">전체</option>
            </select>
          </label>
        </div>
      </header>
      {subjects.length?<nav className="student-exam-subject-tabs" aria-label="과목">{subjects.map(value=><button type="button" key={value} className={selectedSubject===value?"active":""} onClick={()=>setSubject(value)}>{value}</button>)}</nav>:null}
      {scored.length ? (
        <>
          <div className="student-exam-summary"><div><span>최근 점수</span><b>{latest===null?"–":`${latest}점`}</b></div><div><span>최근 3회 평균</span><b>{average===null?"–":`${average}점`}</b></div><div><span>직전 대비</span><b className={delta===null?"":delta>0?"up":delta<0?"down":""}>{delta===null?"–":delta>0?`+${delta}점`:delta===0?"변동 없음":`${delta}점`}</b></div><div><span>선택 기간 시험</span><b>{scored.length}회</b></div></div>
          <div className={`student-exam-bars ${source}`} style={{gridTemplateColumns:`repeat(${scored.length},minmax(64px,1fr))`}} role="img" aria-label={`${sourceLabel(source)} ${selectedSubject} ${range==="week"?"최근 7일":range==="month"?"최근 30일":range==="quarter"?"최근 90일":"전체"} 시험 성적`}>
            {scored.map(item=><article key={item.id} title={`${item.examTitle||examTypeLabel(item.examType)} · ${item.score}/${item.maxScore}`}><div><i style={{height:`${Math.max(5,Math.min(100,item.percent??0))}%`}}><b>{item.percent}점</b></i></div><strong>{item.examTitle||examTypeLabel(item.examType)}</strong><small>{formatDate(item.lessonDate)}</small></article>)}
          </div>
          <div className="student-exam-records">
            {scored
              .slice()
              .reverse()
              .map((item) => (
                <article key={item.id}>
                  <span>
                    <b>{item.examTitle || examTypeLabel(item.examType)}</b>
                    <small>
                      {formatDate(item.lessonDate)} · {item.className}
                    </small>
                  </span>
                  <strong>
                    {item.score}/{item.maxScore} · 환산 {item.percent}점
                  </strong>
                </article>
              ))}
          </div>
        </>
      ) : (
        <Empty text={`아직 점수가 입력된 ${sourceLabel(source)} 시험이 없습니다.`} />
      )}
    </section>
  );
}

function examTypeLabel(value: string) {
  return (
    (
      {
        vocabulary: "영단어 시험",
        weekly: "주간평가",
        monthly: "월간평가",
        mock: "모의고사",
        custom: "기타 시험",
      } as Record<string, string>
    )[value] || "시험"
  );
}
type ExamSourceFilter="all"|ExamProgressItem["source"];
function sourceLabel(value:ExamSourceFilter){return value==="all"?"전체 수업":value==="regular"?"정규수업":value==="correction"?"첨삭수업":value==="makeup"?"보강수업":"추가수업"}
function ClassesTab({ classes, onAssign }: { classes: ClassItem[]; onAssign?: () => void }) {
  return (
    <>
      <div className="hub-section-title class-section-title">
        <div>
          <h3>수강 클래스</h3>
          <p>현재 및 이전 수강 기록입니다.</p>
        </div>
        {onAssign && (
          <button className="primary" onClick={onAssign}>
            ＋ 클래스 배정
          </button>
        )}
      </div>
      <div className="student-record-list">
        {classes.length ? (
          classes.map((item) => (
            <article key={item.id}>
              <i className={item.status} style={item.status === "active" ? { background: item.color ?? "#922D61" } : undefined} />
              <span>
                <b>{item.name}</b>
                <small>
                  {item.subject}
                  {item.room ? ` · ${item.room}` : ""} · {item.teachers || "담당 미배정"}
                </small>
              </span>
              <em>{item.status === "active" ? "수강 중" : item.status === "paused" ? "일시 중지" : "종료"}</em>
            </article>
          ))
        ) : (
          <Empty text="수강 기록이 없습니다." />
        )}
      </div>
    </>
  );
}
function AttendanceTab({ attendance, correctionAttendance, makeups }: { attendance: AttendanceItem[]; correctionAttendance: CorrectionAttendanceItem[]; makeups: MakeupItem[] }) {
  const[source,setSource]=useState<"all"|"regular"|"correction">("all");
  const[range,setRange]=useState<"7"|"30"|"90"|"all">("30");
  const[makeupRange,setMakeupRange]=useState<"7"|"30"|"90"|"all">("30");
  const cutoff=useMemo(()=>range==="all"?null:dateDaysAgo(Number(range)-1),[range]);
  const makeupCutoff=useMemo(()=>makeupRange==="all"?null:dateDaysAgo(Number(makeupRange)-1),[makeupRange]);
  const rows=useMemo(()=>[
    ...attendance.map(item=>({...item,source:"regular" as const})),
    ...correctionAttendance.map(item=>({...item,source:"correction" as const})),
  ].filter(item=>(source==="all"||item.source===source)&&(!cutoff||item.lessonDate>=cutoff)).sort((a,b)=>b.lessonDate.localeCompare(a.lessonDate)),[attendance,correctionAttendance,source,cutoff]);
  const sortedMakeups=useMemo(()=>makeups.filter(item=>!makeupCutoff||dateKey(item.scheduledAt)>=makeupCutoff).sort((a,b)=>b.scheduledAt.localeCompare(a.scheduledAt)),[makeups,makeupCutoff]);
  return (
    <>
      <div className="hub-section-title">
        <div>
          <h3>최근 출결</h3>
          <p>정규수업과 첨삭수업 출결을 선택한 기간으로 확인합니다.</p>
        </div>
        <div className="student-record-selects"><label><span>수업 구분</span><select value={source} onChange={event=>setSource(event.target.value as typeof source)}><option value="all">전체 수업</option><option value="regular">정규수업</option><option value="correction">첨삭수업</option></select></label><label><span>조회 기간</span><select value={range} onChange={event=>setRange(event.target.value as typeof range)}><option value="7">최근 1주</option><option value="30">최근 30일</option><option value="90">최근 90일</option><option value="all">전체 기록</option></select></label></div>
      </div>
      <div className="student-record-list">
        {rows.length ? (
          rows.map((item) => (
            <article key={item.id}>
              <time>{formatDate(item.lessonDate)}</time>
              <span>
                <b>{item.className}<small className={`record-source ${item.source}`}>{item.source==="regular"?"정규":"첨삭"}</small></b>
                <small>{item.note || "메모 없음"}</small>
              </span>
              <em className={item.status}>{statusLabels[item.status]}</em>
            </article>
          ))
        ) : (
          <Empty text="입력된 출결 기록이 없습니다." />
        )}
      </div>
      <div className="hub-section-title compact">
        <div>
          <h3>보강 일정</h3>
          <p>결석 연계 보강·개별 보강·추가수업을 함께 표시합니다.</p>
        </div>
        <label className="student-record-period-select"><span>조회 기간</span><select value={makeupRange} onChange={event=>setMakeupRange(event.target.value as typeof makeupRange)}><option value="7">최근 1주 이후</option><option value="30">최근 30일 이후</option><option value="90">최근 90일 이후</option><option value="all">전체 일정</option></select></label>
      </div>
      <div className="student-record-list">
        {sortedMakeups.length ? (
          sortedMakeups.map((item) => (
            <article key={item.id}>
              <time>{formatDateTime(item.scheduledAt)}</time>
              <span>
                <b>
                  {item.className} · {item.teacherName}<small className={`record-source makeup-${item.recordKind??"absence_makeup"}`}>{item.recordKind==="additional"?"추가수업":item.recordKind==="individual_makeup"?"개별 보강":"결석 연계"}</small>
                </b>
                <small>
                  {item.room}
                  {item.note ? ` · ${item.note}` : ""}
                </small>
              </span>
              <em>{item.status === "scheduled" ? "예정" : item.status === "completed" ? "완료" : "취소"}</em>
            </article>
          ))
        ) : (
          <Empty text="보강 일정이 없습니다." />
        )}
      </div>
    </>
  );
}
function LearningTab({ assignments, corrections, consultations }: { assignments: AssignmentItem[]; corrections: CorrectionLearningItem[]; consultations: ConsultationItem[] }) {
  return (
    <>
      <div className="hub-section-title">
        <div>
          <h3>최근 정규수업 과제</h3>
          <p>정규수업에서 등록한 최근 과제 20건입니다.</p>
        </div>
      </div>
      <div className="hub-section-title compact"><div><h3>최근 첨삭수업 기록</h3><p>첨삭 내용·숙제 검사·피드백을 함께 표시합니다.</p></div></div>
      <div className="student-record-list correction-learning-list">
        {corrections.length?corrections.map(item=><article key={item.id}><time>{formatDate(item.lessonDate)}</time><span><b>{item.subject} 첨삭</b><small>{[item.correctionContent,item.homeworkInstruction,item.homeworkNote,item.assistantFeedback].filter(Boolean).join(" · ")||"기록 내용 없음"}</small></span><em>{correctionHomeworkLabel(item.homeworkStatus)}</em></article>):<Empty text="등록된 첨삭수업 기록이 없습니다."/>}
      </div>
      <div className="student-record-list">
        {assignments.length ? (
          assignments.map((item) => (
            <article key={item.id}>
              <time>{formatDate(item.dueAt)} 마감</time>
              <span>
                <b>{item.title}</b>
                <small>
                  {item.className}
                  {item.feedback ? ` · ${item.feedback}` : ""}
                </small>
              </span>
              <em className={item.status}>{item.status === "reviewed" ? "첨삭 완료" : item.status === "submitted" ? "첨삭 대기" : "제출 전"}</em>
            </article>
          ))
        ) : (
          <Empty text="등록된 과제가 없습니다." />
        )}
      </div>
      <div className="hub-section-title compact">
        <div>
          <h3>최근 상담</h3>
          <p>교직원 내부 기록입니다.</p>
        </div>
      </div>
      <div className="consultation-timeline">
        {consultations.length ? (
          consultations.map((item) => (
            <article key={item.id}>
              <time>{formatDateTime(item.consultedAt)}</time>
              <span>
                <b>
                  {consultationLabels[item.type] || item.type} 상담 · {item.consultantName}
                </b>
                <p>{item.internalNote || "내부 메모 없음"}</p>
                {item.nextContactOn && <small>다음 연락 {formatDate(item.nextContactOn)}</small>}
              </span>
            </article>
          ))
        ) : (
          <Empty text="상담 기록이 없습니다." />
        )}
      </div>
    </>
  );
}
function Empty({ text }: { text: string }) {
  return <p className="student-hub-empty">{text}</p>;
}
function attendanceRate(value:AttendanceSummary){return value.attendanceTotal?Math.round(value.present/value.attendanceTotal*100):null}
function correctionHomeworkLabel(value:string){return value==="reviewed"||value==="completed"?"검사 완료":value==="submitted"?"검사 대기":value?"미완료":"첨삭 기록"}
function dateDaysAgo(days:number){const date=new Date();date.setHours(0,0,0,0);date.setDate(date.getDate()-days);return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(date)}
function dateKey(value:string){return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date(value))}
function formatDate(value: string) {
  return new Intl.DateTimeFormat("ko-KR", {
    timeZone: "Asia/Seoul",
    month: "short",
    day: "numeric",
  }).format(new Date(value));
}
function formatDateTime(value: string) {
  return new Intl.DateTimeFormat("ko-KR", {
    timeZone: "Asia/Seoul",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(new Date(value));
}
function studentStatus(value: string) {
  return value === "active" || value === "재원" ? "재원" : value === "paused" || value === "휴원" ? "휴원" : "퇴원";
}
