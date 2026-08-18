"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { CSSProperties } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";

type Status = "present" | "late" | "absent";
type Student = {
  id: string;
  name: string;
  school: string | null;
  grade: string | null;
  status: Status | "excused" | null;
  lateMinutes: number | null;
  absenceReason: string | null;
  note: string | null;
};
type ExamDraft = {
  id: string;
  examType: string;
  examTitle: string;
  score: string;
  maxScore: string;
  evaluation: string;
};
type Row = Omit<Student, "status"> & {
  status: Status | null;
  exams: ExamDraft[];
  assignedHomework: string;
  previousHomework: string;
  inspectionStatus: string;
  inspectionNote: string;
};
type CalendarDay = {
  date: string;
  scheduled: boolean;
  students: { id: string; name: string; status: Status | "excused" }[];
};
type ExamResult = {
  studentId: string;
  exams: {
    id: string;
    examType: string | null;
    examTitle: string | null;
    score: number | null;
    maxScore: number | null;
    evaluation: string | null;
  }[];
};
type HomeworkResult = {
  studentId: string;
  assignedHomework: string | null;
  previousHomework: string | null;
  inspectionStatus: string | null;
  inspectionNote: string | null;
};
type ExamCategory = {
  id: string;
  name: string;
  isActive: boolean;
  sortOrder: number;
};
type FamilyReadStudent = {
  studentId: string;
  studentName: string;
  school: string | null;
  grade: string | null;
  guardianCount: number;
  readCount: number;
  status: "confirmed" | "unconfirmed" | "unlinked";
  viewedAt: string | null;
};
type FamilyReadStatus = {
  lessonId: string | null;
  totalStudents: number;
  linkedStudents: number;
  confirmedStudents: number;
  unconfirmedStudents: number;
  unlinkedStudents: number;
  students: FamilyReadStudent[];
};

const attendance: [Status, string][] = [
  ["present", "출석"],
  ["late", "지각"],
  ["absent", "결석"],
];
const homework = [
  ["", "미검사"],
  ["complete", "완료"],
  ["partial", "일부"],
  ["missing", "미제출"],
  ["excused", "면제"],
];
const weekdays = ["월", "화", "수", "목", "금", "토", "일"];
const emptyExam = (): ExamDraft => ({
  id: "",
  examType: "",
  examTitle: "",
  score: "",
  maxScore: "100",
  evaluation: "",
});

export function ClassLearningBoard({ supabase, classId, date, students, onDate, onReload }: { supabase: SupabaseClient; classId: string; date: string; students: Student[]; validDay: boolean; onDate: (v: string) => void; onReload: () => Promise<void> }) {
  const [rows, setRows] = useState<Row[]>([]);
  const [week, setWeek] = useState<CalendarDay[]>([]);
  const [notice, setNotice] = useState("");
  const [categories, setCategories] = useState<ExamCategory[]>([]);
  const [categoryOpen, setCategoryOpen] = useState(false);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState("");
  const [error, setError] = useState("");
  const [monthOpen, setMonthOpen] = useState(false);

  const loadWeek = useCallback(async () => {
    const { data } = await supabase.rpc("staff_class_attendance_calendar", {
      p_class_id: classId,
      p_anchor_date: date,
      p_view: "week",
    });
    setWeek((data ?? []) as CalendarDay[]);
  }, [classId, date, supabase]);

  const loadCategories = useCallback(async () => {
    const { data, error: categoryError } = await supabase.rpc("staff_exam_categories");
    if (categoryError) setError(categoryError.message);
    else setCategories((data ?? []) as ExamCategory[]);
  }, [supabase]);

  useEffect(() => {
    let active = true;
    setLoading(true);
    void Promise.all([
      supabase.rpc("staff_class_exam_results", {
        p_class_id: classId,
        p_date: date,
      }),
      supabase.rpc("staff_class_homework_results", {
        p_class_id: classId,
        p_date: date,
      }),
      supabase.rpc("staff_class_attendance_calendar", {
        p_class_id: classId,
        p_anchor_date: date,
        p_view: "week",
      }),
      supabase.rpc("staff_class_daily_notice", {
        p_class_id: classId,
        p_date: date,
      }),
      supabase.rpc("staff_exam_categories"),
    ]).then(([examResponse, homeworkResponse, weekResponse, noticeResponse, categoryResponse]) => {
      if (!active) return;
      if (examResponse.error || homeworkResponse.error || weekResponse.error || noticeResponse.error || categoryResponse.error) {
        setError("개인별 기록을 불러오지 못했습니다. DB 최신 적용 여부를 확인해 주세요.");
        setLoading(false);
        return;
      }
      const examsByStudent = new Map(((examResponse.data ?? []) as ExamResult[]).map((item) => [item.studentId, item]));
      const homeworkByStudent = new Map(((homeworkResponse.data ?? []) as HomeworkResult[]).map((item) => [item.studentId, item]));
      setRows(
        students.map((student) => {
          const exam = examsByStudent.get(student.id)?.exams?.[0];
          const homeworkRow = homeworkByStudent.get(student.id);
          return {
            ...student,
            status: student.status === "excused" ? "absent" : student.status,
            exams: [
              exam
                ? {
                    id: exam.id,
                    examType: exam.examType ?? "",
                    examTitle: exam.examTitle ?? "",
                    score: exam.score == null ? "" : String(exam.score),
                    maxScore: String(exam.maxScore ?? 100),
                    evaluation: exam.evaluation ?? "",
                  }
                : emptyExam(),
            ],
            assignedHomework: homeworkRow?.assignedHomework ?? "",
            previousHomework: homeworkRow?.previousHomework ?? "",
            inspectionStatus: homeworkRow?.inspectionStatus ?? "",
            inspectionNote: homeworkRow?.inspectionNote ?? "",
          };
        }),
      );
      setCategories((categoryResponse.data ?? []) as ExamCategory[]);
      setWeek((weekResponse.data ?? []) as CalendarDay[]);
      setNotice(noticeResponse.data ?? "");
      setError("");
      setLoading(false);
    });
    return () => {
      active = false;
    };
  }, [classId, date, students, supabase]);

  const update = (id: string, patch: Partial<Row>) => setRows((current) => current.map((row) => (row.id === id ? { ...row, ...patch } : row)));
  const updateExam = (studentId: string, patch: Partial<ExamDraft>) => setRows((current) => current.map((row) => (row.id === studentId ? { ...row, exams: [{ ...row.exams[0], ...patch }] } : row)));

  const saveAttendance = async (row: Row, status: Status) => {
    setSaving(row.id);
    setError("");
    if (row.status === status) {
      const { error: clearError } = await supabase.rpc("staff_clear_class_attendance", { p_class_id: classId, p_date: date, p_student_id: row.id });
      if (clearError) setError(clearError.message);
      else {
        update(row.id, {
          status: null,
          lateMinutes: null,
          absenceReason: null,
        });
        await loadWeek();
      }
      setSaving("");
      return;
    }
    let late: number | null = null,
      reason: string | null = null;
    if (status === "late") {
      const value = prompt(`${row.name} 학생은 몇 분 지각했나요?`, String(row.lateMinutes ?? 10));
      if (value === null) {
        setSaving("");
        return;
      }
      late = Number(value);
      if (!Number.isFinite(late) || late < 1) {
        setSaving("");
        setError("지각 시간을 숫자로 입력해 주세요.");
        return;
      }
    }
    if (status === "absent") {
      const value = prompt(`${row.name} 학생의 결석 사유`, row.absenceReason ?? "");
      if (value === null) {
        setSaving("");
        return;
      }
      reason = value.trim();
      if (!reason) {
        setSaving("");
        setError("결석 사유를 입력해 주세요.");
        return;
      }
    }
    const { error: saveError } = await supabase.rpc("staff_save_class_attendance", {
      p_class_id: classId,
      p_date: date,
      p_student_id: row.id,
      p_status: status,
      p_late_minutes: late,
      p_absence_reason: reason,
      p_note: row.note,
    });
    if (saveError) setError(saveError.message);
    else {
      update(row.id, { status, lateMinutes: late, absenceReason: reason });
      await loadWeek();
      if (status === "absent") {
        alert("결석이 저장되었습니다. 보강이 필요하면 클래스 목록의 회색 ‘개별 보강·추가수업’ 블록에서 일정을 등록해 주세요.");
      }
    }
    setSaving("");
  };

  const save = async () => {
    for (const row of rows) {
      const exam = row.exams[0];
      if (exam.score !== "" && (!Number.isFinite(+exam.score) || +exam.score < 0 || +exam.score > +exam.maxScore)) {
        setError(`${row.name} 학생의 점수를 확인해 주세요.`);
        return;
      }
    }
    setSaving("all");
    setError("");
    const examPayload = rows.map((row) => ({
      studentId: row.id,
      exams: [
        {
          ...row.exams[0],
          id: row.exams[0].id || null,
          examType: row.exams[0].examType || null,
          examTitle: row.exams[0].examTitle.trim() || null,
          score: row.exams[0].score === "" ? null : +row.exams[0].score,
          maxScore: +row.exams[0].maxScore,
          evaluation: row.exams[0].evaluation.trim() || null,
        },
      ],
    }));
    const homeworkPayload = rows.map((row) => ({
      studentId: row.id,
      assignedHomework: row.assignedHomework.trim() || null,
      inspectionStatus: row.inspectionStatus || null,
      inspectionNote: row.inspectionNote.trim() || null,
    }));
    const [examResponse, homeworkResponse, noticeResponse] = await Promise.all([
      supabase.rpc("staff_save_class_exam_results", {
        p_class_id: classId,
        p_date: date,
        p_results: examPayload,
      }),
      supabase.rpc("staff_save_class_homework_results", {
        p_class_id: classId,
        p_date: date,
        p_results: homeworkPayload,
      }),
      supabase.rpc("staff_save_class_daily_notice", {
        p_class_id: classId,
        p_date: date,
        p_content: notice,
      }),
    ]);
    if (examResponse.error || homeworkResponse.error || noticeResponse.error) setError(examResponse.error?.message ?? homeworkResponse.error?.message ?? noticeResponse.error?.message ?? "저장하지 못했습니다.");
    else await onReload();
    setSaving("");
  };

  return (
    <section className="class-learning-board">
      <header>
        <div>
          <h3>이번 주 출석부</h3>
          <p>학생별 출석·시험·지난 숙제 검사·오늘 숙제를 한 화면에서 기록합니다.</p>
        </div>
        <div className="learning-header-actions">
          <button className="secondary-button" onClick={() => setMonthOpen(true)}>
            전체 출석 캘린더
          </button>
        </div>
      </header>
      <div className="class-week-strip">
        {week.map((day, index) => (
          <button key={day.date} className={`${day.date === date ? "active" : ""} ${day.scheduled ? "scheduled" : ""}`} onClick={() => onDate(day.date)}>
            <span>{weekdays[index]}</span>
            <b>{+day.date.slice(8)}</b>
            <div>
              {day.students.slice(0, 4).map((student) => (
                <em className={student.status === "excused" ? "absent" : student.status} key={student.id}>
                  {student.name}
                </em>
              ))}
              {!day.students.length ? <small>{day.scheduled ? "출석 전" : "수업 없음"}</small> : null}
            </div>
          </button>
        ))}
      </div>
      <label className="class-daily-notice">
        <b>반 전체 공지사항</b>
        <textarea value={notice} onChange={(event) => setNotice(event.target.value)} placeholder="준비물·일정·반 전체 안내" rows={2} />
      </label>
      <FamilyReportReadStatus supabase={supabase} classId={classId} date={date} />
      <div className="learning-board-heading">
        <span>학생·출결</span>
        <span>개인별 시험</span>
        <span>지난 숙제 검사</span>
        <span>오늘 내줄 숙제</span>
      </div>
      {loading ? (
        <p className="settings-empty">불러오는 중이에요…</p>
      ) : (
        <div className="learning-board-rows">
          {rows.map((row) => {
            const exam = row.exams[0],
              score = Number(exam.score),
              max = Number(exam.maxScore);
            const converted = exam.score !== "" && Number.isFinite(score) && Number.isFinite(max) && max > 0 ? Math.round((score / max) * 1000) / 10 : null;
            return (
              <article key={row.id}>
                <div className="learning-person-attendance">
                  <span className="learning-student">
                    <i>{row.name[0]}</i>
                    <b>{row.name}</b>
                    <small>{[row.school, row.grade].filter(Boolean).join(" · ")}</small>
                  </span>
                  <div className="learning-attendance">
                    {attendance.map(([status, label]) => (
                      <button key={status} className={`${status} ${row.status === status ? "active" : ""}`} disabled={saving === row.id} onClick={() => void saveAttendance(row, status)}>
                        {label}
                      </button>
                    ))}
                    {row.status === "late" ? <small>{row.lateMinutes}분 지각 · 같은 버튼을 다시 누르면 취소</small> : null}
                    {row.status === "absent" ? <small>{row.absenceReason ? `${row.absenceReason} · ` : ""}같은 버튼을 다시 누르면 취소</small> : null}
                    {row.status === "present" ? <small>같은 버튼을 다시 누르면 취소</small> : null}
                  </div>
                </div>
                <div className="learning-exam-list">
                  <div className="learning-exam-card">
                    <div className="learning-exam-card-actions">
                      <b>개인별 시험</b>
                      <button type="button" onClick={() => setCategoryOpen(true)}>
                        카테고리 관리
                      </button>
                    </div>
                    <div className="learning-exam individual">
                      <select value={exam.examType} onChange={(event) => updateExam(row.id, { examType: event.target.value })}>
                        <option value="">종류 선택</option>
                        {categories
                          .filter((category) => category.isActive || category.name === exam.examType)
                          .map((category) => (
                            <option value={category.name} key={category.id}>
                              {category.name}
                            </option>
                          ))}
                      </select>
                      <input value={exam.examTitle} onChange={(event) => updateExam(row.id, { examTitle: event.target.value })} placeholder="시험명·범위" />
                      <span>
                        <input inputMode="decimal" value={exam.score} onChange={(event) => updateExam(row.id, { score: event.target.value })} placeholder="원점수" />
                        <em>/</em>
                        <input inputMode="decimal" value={exam.maxScore} onChange={(event) => updateExam(row.id, { maxScore: event.target.value })} placeholder="만점" />
                      </span>
                      <input value={exam.evaluation} onChange={(event) => updateExam(row.id, { evaluation: event.target.value })} placeholder="평가·피드백" />
                    </div>
                    <small className="exam-percent">{converted === null ? "점수를 입력하면 100점 환산점수가 표시됩니다." : `원점수 ${exam.score}/${exam.maxScore} · 환산 ${converted}점`}</small>
                  </div>
                </div>
                <div className="learning-homework previous">
                  <p>{row.previousHomework || "지난 숙제 없음"}</p>
                  <select value={row.inspectionStatus} onChange={(event) => update(row.id, { inspectionStatus: event.target.value })}>
                    {homework.map(([value, label]) => (
                      <option value={value} key={value}>
                        {label}
                      </option>
                    ))}
                  </select>
                  <input value={row.inspectionNote} onChange={(event) => update(row.id, { inspectionNote: event.target.value })} placeholder="검사 메모" />
                </div>
                <div className="learning-homework assigned">
                  <textarea value={row.assignedHomework} onChange={(event) => update(row.id, { assignedHomework: event.target.value })} placeholder="교재·페이지·문제 번호·제출일" rows={4} />
                </div>
              </article>
            );
          })}
          {!rows.length ? (
            <div className="makeup-empty">
              <p>이 날짜에 등록된 정규 수강생이 없습니다.</p>
            </div>
          ) : null}
        </div>
      )}
      {error ? <p className="form-error learning-board-error">{error}</p> : null}
      <footer>
        <span>출결은 즉시 저장되며, 지난 숙제는 이전 수업 기록에서 자동으로 이어집니다.</span>
        <button className="primary" disabled={saving === "all" || !rows.length} onClick={() => void save()}>
          {saving === "all" ? "저장 중…" : "개인별 기록 저장"}
        </button>
      </footer>
      {monthOpen ? (
        <Month
          supabase={supabase}
          classId={classId}
          anchor={date}
          onDate={(value) => {
            onDate(value);
            setMonthOpen(false);
          }}
          onClose={() => setMonthOpen(false)}
        />
      ) : null}
      {categoryOpen ? <ExamCategoryModal supabase={supabase} categories={categories} onClose={() => setCategoryOpen(false)} onChanged={loadCategories} /> : null}
    </section>
  );
}

function FamilyReportReadStatus({ supabase, classId, date }: { supabase: SupabaseClient; classId: string; date: string }) {
  const [data, setData] = useState<FamilyReadStatus | null>(null);
  const [open, setOpen] = useState(false);
  const [loading, setLoading] = useState(true);
  const [available, setAvailable] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    const { data: next, error } = await supabase.rpc("staff_class_family_report_read_status", {
      p_class_id: classId,
      p_date: date,
    });
    if (error) {
      setAvailable(false);
      setData(null);
    } else {
      setAvailable(true);
      setData(next as FamilyReadStatus);
    }
    setLoading(false);
  }, [classId, date, supabase]);

  useEffect(() => {
    void load();
  }, [load]);

  if (!available) return null;
  const confirmed = data?.confirmedStudents ?? 0;
  const unconfirmed = data?.unconfirmedStudents ?? 0;
  const unlinked = data?.unlinkedStudents ?? 0;
  return (
    <section className="family-read-status">
      <button type="button" className="family-read-summary" onClick={() => setOpen((value) => !value)} disabled={loading}>
        <span>
          <small>학부모 학습리포트</small>
          <b>{!data?.lessonId ? "리포트 생성 전" : `확인 ${confirmed}명 · 미확인 ${unconfirmed}명`}</b>
        </span>
        <span className="family-read-pills">
          {data?.lessonId ? <em className="confirmed">확인 {confirmed}</em> : null}
          {data?.lessonId && unconfirmed ? <em className="unconfirmed">미확인 {unconfirmed}</em> : null}
          {unlinked ? <em className="unlinked">학부모 미연결 {unlinked}</em> : null}
          <strong>{open ? "접기" : "학생별 보기"}</strong>
        </span>
      </button>
      {open && data ? (
        <div className="family-read-details">
          {data.students.map((student) => (
            <article key={student.studentId}>
              <span>
                <b>{student.studentName}</b>
                <small>{[student.school, student.grade].filter(Boolean).join(" · ") || "학생 정보"}</small>
              </span>
              <span className={`family-read-state ${student.status}`}>
                {student.status === "confirmed" ? "학부모 확인" : student.status === "unconfirmed" ? "미확인" : "학부모 계정 미연결"}
                {student.status === "confirmed" && student.viewedAt ? <small>{formatReadTime(student.viewedAt)}</small> : null}
              </span>
            </article>
          ))}
          {!data.students.length ? <p>이 날짜의 수강 학생이 없습니다.</p> : null}
          <footer>
            <span>학부모 또는 보호자 계정 중 한 명이라도 확인하면 ‘학부모 확인’으로 표시됩니다.</span>
            <button type="button" onClick={() => void load()}>새로고침</button>
          </footer>
        </div>
      ) : null}
    </section>
  );
}

function ExamCategoryModal({ supabase, categories, onClose, onChanged }: { supabase: SupabaseClient; categories: ExamCategory[]; onClose: () => void; onChanged: () => Promise<void> }) {
  const [name, setName] = useState("");
  const [saving, setSaving] = useState("");
  const [error, setError] = useState("");
  const add = async () => {
    if (!name.trim()) return;
    setSaving("new");
    const { error: addError } = await supabase.rpc("staff_add_exam_category", {
      p_name: name.trim(),
    });
    if (addError) setError(addError.message);
    else {
      setName("");
      await onChanged();
    }
    setSaving("");
  };
  const change = async (category: ExamCategory, mode: "rename" | "active") => {
    let nextName = category.name;
    if (mode === "rename") {
      const value = prompt("시험 카테고리 이름", category.name);
      if (value === null || !value.trim()) return;
      nextName = value.trim();
    }
    setSaving(category.id);
    const { error: changeError } = await supabase.rpc("staff_set_exam_category", {
      p_id: category.id,
      p_name: nextName,
      p_active: mode === "active" ? !category.isActive : category.isActive,
    });
    if (changeError) setError(changeError.message);
    else await onChanged();
    setSaving("");
  };
  return (
    <div className="modal-backdrop nested">
      <section className="student-modal exam-category-modal">
        <header>
          <div>
            <p className="eyebrow">개인 설정</p>
            <h2>시험 카테고리 관리</h2>
            <span>선생님별로 시험 종류를 추가하고 이름을 바꾸거나 사용 중지할 수 있습니다.</span>
          </div>
          <button onClick={onClose}>×</button>
        </header>
        <div className="exam-category-add">
          <input
            autoFocus
            value={name}
            onChange={(event) => setName(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Enter") void add();
            }}
            placeholder="새 시험 카테고리"
          />
          <button className="primary" disabled={saving === "new"} onClick={() => void add()}>
            추가
          </button>
        </div>
        <div className="exam-category-list">
          {categories.map((category) => (
            <article key={category.id} className={category.isActive ? "" : "inactive"}>
              <b>{category.name}</b>
              <span>
                <button className="secondary-button" disabled={saving === category.id} onClick={() => void change(category, "rename")}>
                  이름 변경
                </button>
                <button className="secondary-button" disabled={saving === category.id} onClick={() => void change(category, "active")}>
                  {category.isActive ? "사용 중지" : "다시 사용"}
                </button>
              </span>
            </article>
          ))}
        </div>
        {error ? <p className="form-error">{error}</p> : null}
        <footer>
          <button className="primary" onClick={onClose}>
            완료
          </button>
        </footer>
      </section>
    </div>
  );
}

function Month({ supabase, classId, anchor, onDate, onClose }: { supabase: SupabaseClient; classId: string; anchor: string; onDate: (v: string) => void; onClose: () => void }) {
  const [month, setMonth] = useState(anchor.slice(0, 7));
  const [days, setDays] = useState<CalendarDay[]>([]);
  useEffect(() => {
    void supabase
      .rpc("staff_class_attendance_calendar", {
        p_class_id: classId,
        p_anchor_date: `${month}-01`,
        p_view: "month",
      })
      .then(({ data }) => setDays(data ?? []));
  }, [classId, month, supabase]);
  const offset = days.length ? isoWeekday(days[0].date) - 1 : 0;
  return (
    <div className="modal-backdrop nested">
      <section className="student-modal class-month-modal">
        <header>
          <div>
            <p className="eyebrow">전체 출결 현황</p>
            <h2>출석 캘린더</h2>
          </div>
          <button onClick={onClose}>×</button>
        </header>
        <label className="month-picker">
          조회 월
          <input type="month" value={month} onChange={(event) => setMonth(event.target.value)} />
        </label>
        <div className="month-calendar">
          <div className="month-weekdays">
            {weekdays.map((day) => (
              <b key={day}>{day}</b>
            ))}
          </div>
          <div className="month-days" style={{ "--first-offset": offset } as CSSProperties}>
            {days.map((day) => (
              <button key={day.date} className={day.scheduled ? "scheduled" : ""} onClick={() => onDate(day.date)}>
                <b>{+day.date.slice(8)}</b>
                <span>
                  {day.students.map((student) => (
                    <em className={student.status === "excused" ? "absent" : student.status} key={student.id}>
                      {student.name}
                    </em>
                  ))}
                </span>
              </button>
            ))}
          </div>
        </div>
      </section>
    </div>
  );
}

function formatReadTime(value: string) {
  return new Intl.DateTimeFormat("ko-KR", { timeZone: "Asia/Seoul", month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit", hour12: false }).format(new Date(value));
}

function isoWeekday(value: string) {
  const day = new Date(`${value}T00:00:00`).getDay();
  return day === 0 ? 7 : day;
}
