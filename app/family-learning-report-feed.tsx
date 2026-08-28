"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import Holidays from "date-holidays";
import { HansalmaeIcon } from "./hansalmae-icons";
import { appConfirm } from "./app-dialog";
import { familyTeacherName } from "./family-teacher-name";
import {
  CommentReactionBar,
  useReportCommentReactions,
} from "./report-comment-reactions";

let familyModalLockCount = 0;
let familyModalScrollY = 0;

function useFamilyModalScrollLock(enabled = true) {
  useEffect(() => {
    if (!enabled) return;
    if (familyModalLockCount === 0) {
      familyModalScrollY = window.scrollY;
      document.documentElement.classList.add("family-modal-open");
      document.body.classList.add("family-modal-open");
      document.body.style.top = `-${familyModalScrollY}px`;
    }
    familyModalLockCount += 1;
    return () => {
      familyModalLockCount = Math.max(0, familyModalLockCount - 1);
      if (familyModalLockCount === 0) {
        document.documentElement.classList.remove("family-modal-open");
        document.body.classList.remove("family-modal-open");
        document.body.style.top = "";
        window.scrollTo(0, familyModalScrollY);
      }
    };
  }, [enabled]);
}

type AttendanceInfo = {
  status: string;
  lateMinutes: number | null;
  absenceReason: string;
  note: string;
} | null;
type HomeworkResult = { status: string; note: string } | null;
type Exam = {
  id: string;
  examType: string;
  examTitle: string;
  score: number | null;
  maxScore: number;
  percent: number | null;
  evaluation: string;
  feedback: string;
};
type ExamTrendItem = {
  id: string;
  lessonDate: string;
  className: string;
  subject: string;
  mainSubject?: string;
  examType?: string;
  examTitle?: string;
  itemType?: "regular" | "makeup" | "extra" | "correction";
  score: number | null;
  maxScore: number;
  percent: number | null;
};
type ExamTrendRange = "recent" | "3m" | "6m" | "all";
type ExamTrendPoint = {
  id: string;
  label: string;
  lessonDate: string;
  percent: number;
  items: ExamTrendItem[];
};
type Report = {
  lessonId: string;
  lessonDate: string;
  startsAt: string;
  classId: string;
  className: string;
  subject: string;
  mainSubject?: string;
  room: string | null;
  teacherName: string;
  lessonContent: string;
  homeworkContent: string;
  examContent: string;
  attendance: AttendanceInfo;
  homeworkResult: HomeworkResult;
  exams: Exam[];
};
type CorrectionReport = {
  id: string;
  correctionDate: string;
  startTime: string;
  endTime: string;
  subject: string;
  attendanceStatus: string;
  lateMinutes: number | null;
  examTitle: string;
  examRange: string;
  examScore: number | null;
  examMaxScore: number | null;
  evaluation: string;
  homeworkInstruction: string;
  homeworkStatus: string | null;
  homeworkNote: string;
  correctionContent: string;
  assistantFeedback: string;
  nextPreparation: string;
  recordedByName: string | null;
};
type FeedItem =
  | { kind: "lesson"; date: string; time: string; report: Report }
  | {
      kind: "correction";
      date: string;
      time: string;
      report: CorrectionReport;
    };
type ReadReceipt = { lessonId: string; viewedAt: string };
type CorrectionReadReceipt = { reportId: string; viewedAt: string };
type ReportComment = {
  id: string;
  parentId: string | null;
  body: string;
  authorName: string;
  authorRole: string;
  createdAt: string;
  canDelete: boolean;
  isDeleted: boolean;
};

const attendanceLabel: Record<string, string> = {
  present: "출석",
  late: "지각",
  absent: "결석",
  excused: "결석",
};
const homeworkLabel: Record<string, string> = {
  complete: "완료",
  partial: "일부 완료",
  missing: "미제출",
  excused: "확인 제외",
};
const koreanHolidays = new Holidays("KR");

export function FamilyLearningReportFeed({
  supabase,
  studentId,
  studentName,
  displayMode = "feed",
}: {
  supabase: SupabaseClient;
  studentId: string;
  studentName?: string;
  displayMode?: "feed" | "calendar";
}) {
  const [items, setItems] = useState<Report[]>([]);
  const [reads, setReads] = useState<Record<string, string>>({});
  const [corrections, setCorrections] = useState<CorrectionReport[]>([]);
  const [correctionReads, setCorrectionReads] = useState<
    Record<string, string>
  >({});
  const [subject, setSubject] = useState("전체");
  const [loading, setLoading] = useState(true);
  const [unavailable, setUnavailable] = useState(false);
  const [readTracking, setReadTracking] = useState(false);
  const [confirming, setConfirming] = useState<string | null>(null);
  const [selected, setSelected] = useState<FeedItem | null>(null);
  const [canComment, setCanComment] = useState(false);
  const [visibleDayCount, setVisibleDayCount] = useState(5);
  const [calendarMonth, setCalendarMonth] = useState(() => koreaMonth());
  const [selectedDate, setSelectedDate] = useState(() => koreaDate());
  const [refreshing, setRefreshing] = useState(false);
  const [refreshComplete, setRefreshComplete] = useState(false);
  const [pullDistance, setPullDistance] = useState(0);
  const pullStartY = useRef<number | null>(null);
  const refreshCompleteTimer = useRef<number | null>(null);

  useEffect(
    () => () => {
      if (refreshCompleteTimer.current !== null)
        window.clearTimeout(refreshCompleteTimer.current);
    },
    [],
  );

  useEffect(() => {
    let active = true;
    void Promise.resolve().then(async () => {
      if (!active) return;
      setLoading(true);
      setUnavailable(false);
      setReadTracking(false);
      setReads({});
      setCorrections([]);
      setCorrectionReads({});
      setSelected(null);
      const [reportResult, correctionResult] = await Promise.all([
        supabase.rpc("family_completed_learning_reports", {
          p_student_id: studentId,
          p_limit: 20,
        }),
        supabase.rpc("family_correction_reports", {
          p_student_id: studentId,
          p_limit: 20,
        }),
      ]);
      if (!active) return;
      if (reportResult.error) {
        setUnavailable(true);
        setItems([]);
        setLoading(false);
        return;
      }
      setItems((reportResult.data ?? []) as Report[]);
      if (!correctionResult.error)
        setCorrections(
          ((correctionResult.data ?? []) as CorrectionReport[]).map(
            normalizeCorrectionReport,
          ),
        );
      const [readResult, correctionReadResult] = await Promise.all([
        supabase.rpc("family_learning_report_reads", {
          p_student_id: studentId,
        }),
        supabase.rpc("family_correction_report_reads", {
          p_student_id: studentId,
        }),
      ]);
      if (!active) return;
      if (!readResult.error) {
        const next: Record<string, string> = {};
        for (const receipt of (readResult.data ?? []) as ReadReceipt[])
          next[receipt.lessonId] = receipt.viewedAt;
        setReads(next);
        setReadTracking(true);
      }
      if (!correctionReadResult.error) {
        const next: Record<string, string> = {};
        for (const receipt of (correctionReadResult.data ??
          []) as CorrectionReadReceipt[])
          next[receipt.reportId] = receipt.viewedAt;
        setCorrectionReads(next);
      }
      setLoading(false);
    });
    return () => {
      active = false;
    };
  }, [studentId, supabase]);

  const refreshFeed = useCallback(async () => {
    if (refreshing) return;
    const startedAt = Date.now();
    if (refreshCompleteTimer.current !== null)
      window.clearTimeout(refreshCompleteTimer.current);
    setRefreshComplete(false);
    setRefreshing(true);
    const [reportResult, correctionResult, readResult, correctionReadResult] =
      await Promise.all([
        supabase.rpc("family_completed_learning_reports", {
          p_student_id: studentId,
          p_limit: 20,
        }),
        supabase.rpc("family_correction_reports", {
          p_student_id: studentId,
          p_limit: 20,
        }),
        supabase.rpc("family_learning_report_reads", {
          p_student_id: studentId,
        }),
        supabase.rpc("family_correction_report_reads", {
          p_student_id: studentId,
        }),
      ]);
    if (!reportResult.error)
      setItems((reportResult.data ?? []) as Report[]);
    if (!correctionResult.error)
      setCorrections(
        ((correctionResult.data ?? []) as CorrectionReport[]).map(
          normalizeCorrectionReport,
        ),
      );
    if (!readResult.error) {
      const next: Record<string, string> = {};
      for (const receipt of (readResult.data ?? []) as ReadReceipt[])
        next[receipt.lessonId] = receipt.viewedAt;
      setReads(next);
      setReadTracking(true);
    }
    if (!correctionReadResult.error) {
      const next: Record<string, string> = {};
      for (const receipt of (correctionReadResult.data ??
        []) as CorrectionReadReceipt[])
        next[receipt.reportId] = receipt.viewedAt;
      setCorrectionReads(next);
    }
    const remaining = Math.max(0, 650 - (Date.now() - startedAt));
    if (remaining > 0)
      await new Promise((resolve) => window.setTimeout(resolve, remaining));
    setRefreshing(false);
    setRefreshComplete(true);
    refreshCompleteTimer.current = window.setTimeout(() => {
      setRefreshComplete(false);
      refreshCompleteTimer.current = null;
    }, 900);
  }, [refreshing, studentId, supabase]);
  useEffect(() => {
    void supabase
      .rpc("family_can_report_comment")
      .then(({ data, error }) => setCanComment(!error && data === true));
  }, [supabase]);
  useEffect(() => {
    if (loading) return;
    try {
      const detail = JSON.parse(
        sessionStorage.getItem("hansalmae:family-report-target") ?? "null",
      ) as { lessonId?: string; studentId?: string } | null;
      if (
        !detail?.lessonId ||
        (detail.studentId && detail.studentId !== studentId)
      )
        return;
      const target = items.find((item) => item.lessonId === detail.lessonId);
      if (target) {
        setSelected({
          kind: "lesson",
          date: target.lessonDate,
          time: target.startsAt,
          report: target,
        });
        sessionStorage.removeItem("hansalmae:family-report-target");
      }
    } catch {
      sessionStorage.removeItem("hansalmae:family-report-target");
    }
  }, [items, loading, studentId]);
  useEffect(() => {
    const openReport = (event: Event) => {
      const detail = (
        event as CustomEvent<{ lessonId?: string; studentId?: string }>
      ).detail;
      if (
        !detail?.lessonId ||
        (detail.studentId && detail.studentId !== studentId)
      )
        return;
      const target = items.find((item) => item.lessonId === detail.lessonId);
      if (target) {
        setSelected({
          kind: "lesson",
          date: target.lessonDate,
          time: target.startsAt,
          report: target,
        });
        sessionStorage.removeItem("hansalmae:family-report-target");
      }
    };
    window.addEventListener("hansalmae:open-family-report", openReport);
    return () =>
      window.removeEventListener("hansalmae:open-family-report", openReport);
  }, [items, studentId]);

  useEffect(() => {
    if (!selected) return;
    const close = (event: KeyboardEvent) => {
      if (event.key === "Escape") setSelected(null);
    };
    document.addEventListener("keydown", close);
    return () => document.removeEventListener("keydown", close);
  }, [selected]);

  const feedItems = useMemo<FeedItem[]>(
    () => [
      ...items.map((report) => ({
        kind: "lesson" as const,
        date: report.lessonDate,
        time: report.startsAt,
        report,
      })),
      ...corrections.map((report) => ({
        kind: "correction" as const,
        date: report.correctionDate,
        time: report.startTime,
        report,
      })),
    ],
    [corrections, items],
  );
  const subjects = useMemo(
    () => Array.from(new Set(feedItems.map(feedFilterLabel).filter(Boolean))),
    [feedItems],
  );
  const selectedSubject =
    subject === "전체" || subjects.includes(subject) ? subject : "전체";
  const visibleItems = useMemo(
    () =>
      selectedSubject === "전체"
        ? feedItems
        : feedItems.filter((item) => feedFilterLabel(item) === selectedSubject),
    [feedItems, selectedSubject],
  );
  const groups = useMemo(() => {
    const grouped = new Map<string, FeedItem[]>();
    for (const item of visibleItems) {
      const current = grouped.get(item.date) ?? [];
      current.push(item);
      grouped.set(item.date, current);
    }
    return Array.from(grouped.entries())
      .sort(([left], [right]) => right.localeCompare(left))
      .map(
        ([date, reports]) =>
          [
            date,
            reports.sort((left, right) => left.time.localeCompare(right.time)),
          ] as const,
      );
  }, [visibleItems]);
  const displayedGroups = groups.slice(0, visibleDayCount);

  useEffect(() => {
    setVisibleDayCount(5);
  }, [selectedSubject, studentId]);
  const unreadCount =
    (readTracking ? items.filter((item) => !reads[item.lessonId]).length : 0) +
    corrections.filter((item) => !correctionReads[item.id]).length;

  const calendarDays = useMemo(() => buildCalendarDays(calendarMonth), [calendarMonth]);
  const publicHolidayDates = useMemo(() => {
    const year = Number(calendarMonth.slice(0, 4));
    const dates = new Set<string>();
    for (const holiday of koreanHolidays.getHolidays(year)) {
      if (holiday.type !== "public") continue;
      const date = holiday.date.slice(0, 10);
      dates.add(date);
      if (holiday.name === "설날" || holiday.name === "추석") {
        dates.add(shiftDateKey(date, -1));
        dates.add(shiftDateKey(date, 1));
      }
    }
    return dates;
  }, [calendarMonth]);
  const calendarItemsByDate = useMemo(() => {
    const grouped = new Map<string, FeedItem[]>();
    for (const item of feedItems) grouped.set(item.date, [...(grouped.get(item.date) ?? []), item]);
    return grouped;
  }, [feedItems]);
  const selectedCalendarItems = (calendarItemsByDate.get(selectedDate) ?? []).sort((left, right) => left.time.localeCompare(right.time));

  async function confirmRead(lessonId: string) {
    if (!readTracking || reads[lessonId] || confirming) return;
    setConfirming(lessonId);
    const { data, error } = await supabase.rpc(
      "mark_family_learning_report_read",
      { p_student_id: studentId, p_lesson_id: lessonId },
    );
    if (!error)
      setReads((current) => ({
        ...current,
        [lessonId]: String(data ?? new Date().toISOString()),
      }));
    setConfirming(null);
  }

  async function confirmCorrectionRead(reportId: string) {
    if (correctionReads[reportId] || confirming) return;
    setConfirming(reportId);
    const { data, error } = await supabase.rpc(
      "mark_family_correction_report_read",
      {
        p_student_id: studentId,
        p_report_id: reportId,
      },
    );
    if (!error)
      setCorrectionReads((current) => ({
        ...current,
        [reportId]: String(data ?? new Date().toISOString()),
      }));
    setConfirming(null);
  }

  if (unavailable) return null;
  if (displayMode === "calendar") return (
    <section className="family-learning-calendar" aria-label={`${studentName ?? "학생"} 학습캘린더`}>
      <header className="family-calendar-toolbar">
        <button type="button" aria-label="이전 달" onClick={() => setCalendarMonth(shiftMonth(calendarMonth, -1))}>‹</button>
        <div><strong>{formatCalendarMonth(calendarMonth)}</strong><span>출석 기록이 있는 날짜를 선택하세요</span></div>
        <button type="button" aria-label="다음 달" onClick={() => setCalendarMonth(shiftMonth(calendarMonth, 1))}>›</button>
      </header>
      <div className="family-calendar-weekdays" aria-hidden="true">{["일", "월", "화", "수", "목", "금", "토"].map(day => <span key={day}>{day}</span>)}</div>
      <div className="family-calendar-grid">
        {calendarDays.map(day => {
          const dayItems = calendarItemsByDate.get(day.date) ?? [];
          const isSelected = day.date === selectedDate;
          return <button type="button" key={day.date} className={`${day.inMonth ? "" : "outside"} ${isSelected ? "selected" : ""} ${day.date === koreaDate() ? "today" : ""} ${publicHolidayDates.has(day.date) ? "public-holiday" : ""}`} aria-pressed={isSelected} aria-label={`${day.date}${dayItems.length ? `, 학습 기록 ${dayItems.length}개` : ", 학습 기록 없음"}`} onClick={() => setSelectedDate(day.date)}>
            <span>{day.day}</span>
            <i>{dayItems.slice(0, 3).map((item, index) => <em key={`${item.kind}-${item.kind === "lesson" ? item.report.lessonId : item.report.id}-${index}`} className={calendarItemTone(item)} />)}</i>
          </button>;
        })}
      </div>
      <section className="family-calendar-day-panel">
        <header><div><strong>{formatCalendarDate(selectedDate)}</strong><span>{formatDateWeekday(selectedDate)}</span></div><small>{selectedCalendarItems.length ? `${selectedCalendarItems.length}개 기록` : "기록 없음"}</small></header>
        {loading ? <p className="family-report-empty">학습 기록을 불러오는 중이에요…</p> : selectedCalendarItems.length ? <div className="family-calendar-day-list">{selectedCalendarItems.map(item => {
          const title = item.kind === "lesson" ? reportDisplayTitle(item.report) : `${item.report.subject} 첨삭`;
          const attendance = item.kind === "lesson" ? item.report.attendance?.status : item.report.attendanceStatus;
          return <button type="button" key={item.kind === "lesson" ? item.report.lessonId : item.report.id} onClick={() => {
            setSelected(item);
            if (item.kind === "lesson") void confirmRead(item.report.lessonId);
            else void confirmCorrectionRead(item.report.id);
          }}>
            <time>{item.kind === "lesson" ? formatTime(item.time) : item.time.slice(0, 5)}</time><span><strong>{title}</strong><small>{item.kind === "lesson" ? reportBadgeLabel(item.report) : "첨삭수업"}</small></span>{attendance && <em className={attendance}>{attendanceLabel[attendance] ?? attendance}</em>}<b>›</b>
          </button>;
        })}</div> : <div className="family-calendar-empty"><HansalmaeIcon name="calendar" size={24}/><p>이날은 저장된 학습 기록이 없어요.</p></div>}
      </section>
      {selected?.kind === "lesson" && <ReportDetail supabase={supabase} studentId={studentId} item={selected.report} previousHomework={findPreviousLessonHomework(selected.report, items)} canComment={canComment} onClose={() => setSelected(null)} />}
      {selected?.kind === "correction" && <CorrectionFeedDetail supabase={supabase} studentId={studentId} item={selected.report} previousHomework={findPreviousCorrectionHomework(selected.report, corrections)} onClose={() => setSelected(null)} />}
    </section>
  );
  return (
    <section
      className="family-report-feed"
      aria-label="수업 학습 리포트"
      onTouchStart={(event) => {
        if (window.scrollY <= 4)
          pullStartY.current = event.touches[0]?.clientY ?? null;
      }}
      onTouchMove={(event) => {
        if (pullStartY.current === null) return;
        const distance = Math.max(
          0,
          Math.min(72, (event.touches[0]?.clientY ?? 0) - pullStartY.current),
        );
        setPullDistance(distance);
      }}
      onTouchEnd={() => {
        const shouldRefresh = pullDistance >= 48;
        pullStartY.current = null;
        setPullDistance(0);
        if (shouldRefresh) void refreshFeed();
      }}
    >
      {(pullDistance > 0 || refreshing || refreshComplete) && (
        <div
          className={`family-report-pull-refresh${refreshing ? " refreshing" : ""}${refreshComplete ? " complete" : ""}`}
          aria-live="polite"
          role="status"
          style={{
            height:
              refreshing || refreshComplete
                ? 34
                : Math.min(34, Math.max(10, pullDistance * 0.48)),
            opacity: refreshing || refreshComplete ? 1 : Math.min(1, pullDistance / 30),
          }}
        >
          <HansalmaeIcon
            name={refreshComplete ? "check" : "refresh"}
            size={16}
          />
          <span>
            {refreshComplete
              ? "새로운 기록을 확인했어요"
              : refreshing
                ? "새로운 기록을 확인하는 중"
                : pullDistance >= 48
                  ? "놓으면 새 기록을 확인해요"
                  : "조금 더 당겨주세요"}
          </span>
        </div>
      )}
      <header className="family-report-feed-title">
        <div>
          <p className="eyebrow">하루하루 쌓이는 기록</p>
          <h2>{studentName ? `${studentName}의 학습 피드` : "학습 피드"}</h2>
          <span>{studentName ? `오늘 ${withSubjectParticle(studentName)} 무엇을 배우고 어떻게 해냈는지 확인하세요.` : "오늘 무엇을 배우고 어떻게 해냈는지 확인하세요."}</span>
        </div>
        {readTracking && unreadCount > 0 && (
          <strong className="family-report-unread-count">
            새 기록 {unreadCount}
          </strong>
        )}
      </header>
      {subjects.length > 1 && (
        <nav className="family-report-subject-filter" aria-label="과목 필터">
          <button
            type="button"
            className={`family-report-filter-all ${selectedSubject === "전체" ? "active" : ""}`}
            aria-pressed={selectedSubject === "전체"}
            onClick={() => setSubject("전체")}
          >
            전체
          </button>
          <div className="family-report-filter-scroll">
            {subjects.map((name) => (
              <button
                type="button"
                key={name}
                className={selectedSubject === name ? "active" : ""}
                aria-pressed={selectedSubject === name}
                onClick={(event) => {
                  setSubject(name);
                  event.currentTarget.scrollIntoView({
                    behavior: "smooth",
                    block: "nearest",
                    inline: "center",
                  });
                }}
              >
                {name}
              </button>
            ))}
          </div>
        </nav>
      )}
      {loading ? (
        <p className="family-report-empty">학습 기록을 불러오는 중이에요…</p>
      ) : !feedItems.length ? (
        <p className="family-report-empty">아직 도착한 학습 기록이 없습니다.</p>
      ) : (
        <div className="family-report-date-list">
          {displayedGroups.map(([date, reports]) => (
            <section className="family-report-date-group" key={date}>
              <header>
                <div>
                  <time>{formatDateTitle(date)}</time>
                  <span>{formatDateWeekday(date)}</span>
                </div>
                <small>{reports.length}개 수업</small>
              </header>
              <div className="family-report-list">
                {reports.map((item) =>
                  item.kind === "lesson" ? (
                    <ReportCard
                      key={`lesson-${item.report.lessonId}`}
                      item={item.report}
                      readAt={reads[item.report.lessonId] ?? null}
                      readTracking={readTracking}
                      onOpen={() => {
                        setSelected(item);
                        void confirmRead(item.report.lessonId);
                      }}
                    />
                  ) : (
                    <CorrectionFeedCard
                      key={`correction-${item.report.id}`}
                      item={item.report}
                      readAt={correctionReads[item.report.id] ?? null}
                      onOpen={() => {
                        setSelected(item);
                        void confirmCorrectionRead(item.report.id);
                      }}
                    />
                  ),
                )}
              </div>
            </section>
          ))}
          {displayedGroups.length < groups.length && (
            <button
              type="button"
              className="family-report-load-more"
              onClick={() => setVisibleDayCount((count) => count + 5)}
            >
              이전 기록 5일 더 보기
            </button>
          )}
        </div>
      )}
      {selected?.kind === "lesson" && (
        <ReportDetail
          supabase={supabase}
          studentId={studentId}
          item={selected.report}
          previousHomework={findPreviousLessonHomework(selected.report, items)}
          canComment={canComment}
          onClose={() => setSelected(null)}
        />
      )}
      {selected?.kind === "correction" && (
        <CorrectionFeedDetail
          supabase={supabase}
          studentId={studentId}
          item={selected.report}
          previousHomework={findPreviousCorrectionHomework(
            selected.report,
            corrections,
          )}
          onClose={() => setSelected(null)}
        />
      )}
    </section>
  );
}

function koreaDate() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Seoul", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
}
function koreaMonth() { return koreaDate().slice(0, 7); }
function shiftMonth(month: string, amount: number) {
  const [year, value] = month.split("-").map(Number);
  const date = new Date(Date.UTC(year, value - 1 + amount, 1));
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, "0")}`;
}
function shiftDateKey(value: string, amount: number) {
  const date = new Date(`${value}T00:00:00Z`);
  date.setUTCDate(date.getUTCDate() + amount);
  return date.toISOString().slice(0, 10);
}
function buildCalendarDays(month: string) {
  const [year, value] = month.split("-").map(Number);
  const first = new Date(Date.UTC(year, value - 1, 1));
  const start = new Date(first); start.setUTCDate(first.getUTCDate() - first.getUTCDay());
  return Array.from({ length: 42 }, (_, index) => {
    const date = new Date(start); date.setUTCDate(start.getUTCDate() + index);
    const key = `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, "0")}-${String(date.getUTCDate()).padStart(2, "0")}`;
    return { date: key, day: date.getUTCDate(), inMonth: date.getUTCMonth() === value - 1 };
  });
}
function formatCalendarMonth(month: string) { const [year, value] = month.split("-"); return `${year}년 ${Number(value)}월`; }
function formatCalendarDate(date: string) { const [, month, day] = date.split("-"); return `${Number(month)}월 ${Number(day)}일`; }
function calendarItemTone(item: FeedItem) {
  if (item.kind === "correction") return "correction";
  const label = reportBadgeLabel(item.report);
  if (label.includes("보강")) return "makeup";
  if (label.includes("추가")) return "extra";
  return item.report.mainSubject === "수학" || item.report.subject.includes("수학") ? "math" : "regular";
}

function feedFilterLabel(item: FeedItem) {
  return item.kind === "correction" ? "첨삭" : item.report.subject;
}

function CorrectionFeedCard({
  item,
  readAt,
  onOpen,
}: {
  item: CorrectionReport;
  readAt: string | null;
  onOpen: () => void;
}) {
  const unreadAttention = useUnreadAttention(!readAt);
  const examSummary = item.examTitle
    ? `${item.examTitle}${
        item.examScore == null
          ? ""
          : ` ${formatRawExamScore(item.examScore, item.examMaxScore ?? 100, isWordExam(item.examTitle), false)}`
      }`
    : "";
  const assignmentSummary =
    item.homeworkInstruction ||
    (item.homeworkStatus
      ? correctionHomeworkLabel(item.homeworkStatus)
      : "");
  return (
    <article
      ref={unreadAttention.ref}
      className={`family-report-card correction ${!readAt ? "unread" : ""} ${unreadAttention.visible ? "attention-visible" : ""}`}
    >
      <button
        type="button"
        className="family-report-card-main"
        onClick={onOpen}
        aria-label={`${item.subject} 첨삭 리포트 자세히 보기`}
      >
        <span className="family-report-subject">
          <span className="family-report-card-title-row">
            <strong>{item.subject} 첨삭</strong>
            <span className="family-report-card-labels">
              <span>{item.subject} 첨삭</span>
              {!readAt && <em>NEW</em>}
            </span>
          </span>
          <small>
            {item.startTime.slice(0, 5)}–{item.endTime.slice(0, 5)}
            {item.recordedByName
              ? ` · ${familyTeacherName(item.recordedByName)}`
              : ""}
          </small>
          <FeedSummary
            lessonLabel="첨삭내용"
            lesson={item.correctionContent}
            exam={examSummary}
            assignment={assignmentSummary}
          />
        </span>
        <strong className={`family-attendance-badge ${item.attendanceStatus}`}>
          {attendanceLabel[item.attendanceStatus] ??
            (item.attendanceStatus === "scheduled"
              ? "미기록"
              : item.attendanceStatus)}
          {item.attendanceStatus === "late" && item.lateMinutes
            ? ` ${item.lateMinutes}분`
            : ""}
        </strong>
        <span className="family-report-open">
          자세히 보기 <b>›</b>
        </span>
      </button>
    </article>
  );
}

function CorrectionFeedDetail({
  supabase,
  studentId,
  item,
  previousHomework,
  onClose,
}: {
  supabase: SupabaseClient;
  studentId: string;
  item: CorrectionReport;
  previousHomework: string;
  onClose: () => void;
}) {
  useFamilyModalScrollLock();
  const [trendOpen, setTrendOpen] = useState(false);
  const examRange = cleanCorrectionRange(item.examRange);
  const convertedExamScore =
    item.examScore == null ||
    item.examMaxScore == null ||
    Number(item.examMaxScore) <= 0
      ? null
      : Math.round(
          (Number(item.examScore) / Number(item.examMaxScore)) * 1000,
        ) / 10;
  return (
    <div
      className="family-report-detail-backdrop"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <section className={`family-report-detail${trendOpen ? " trend-open" : ""}`} role="dialog" aria-modal="true">
        <header className="family-report-detail-head">
          <button
            type="button"
            onClick={onClose}
            aria-label="첨삭 상세 리포트 닫기"
          >
            ‹
          </button>
          <div>
            <small>{formatFullDate(item.correctionDate)}</small>
            <h2>첨삭 상세 리포트</h2>
          </div>
          <span />
        </header>
        <div className="family-report-detail-scroll">
          <section className="family-report-detail-hero correction">
            <div className="family-report-card-labels">
              <span>{item.subject} 첨삭</span>
            </div>
            <div>
              <h3>{item.subject} 첨삭</h3>
              <strong
                className={`family-attendance-badge ${item.attendanceStatus}`}
              >
                {attendanceLabel[item.attendanceStatus] ??
                  (item.attendanceStatus === "scheduled"
                    ? "미기록"
                    : item.attendanceStatus)}
                {item.attendanceStatus === "late" && item.lateMinutes
                  ? ` ${item.lateMinutes}분`
                  : ""}
              </strong>
            </div>
            <p>
              {item.startTime.slice(0, 5)}–{item.endTime.slice(0, 5)}
              {item.recordedByName
                ? ` · ${familyTeacherName(item.recordedByName)}`
                : ""}
            </p>
          </section>
          <div className="family-report-detail-sections">
            {item.examTitle.trim() && (
              <LabeledReportSection
                icon="chart"
                title="개인별 시험 결과"
                actionLabel="성적 추이 보기"
                onClick={() => setTrendOpen(true)}
                rows={[
                  {
                    label: "시험",
                    value: examRange
                      ? `${item.examTitle} ${examRange}`
                      : item.examTitle,
                  },
                  convertedExamScore !== null
                    ? {
                        label: "점수",
                        value: `${formatRawExamScore(item.examScore!, item.examMaxScore!, isWordExam(item.examTitle))} (${Math.round(convertedExamScore)}점)`,
                      }
                    : null,
                  item.evaluation
                    ? { label: "피드백", value: item.evaluation }
                    : null,
                ]}
              />
            )}
            {item.correctionContent.trim() && (
              <ReportSection
                icon="book"
                title="오늘 한 첨삭과제"
                text={item.correctionContent}
              />
            )}
            {item.homeworkInstruction.trim() && (
              <ReportSection
                icon="edit"
                title="과제 및 복습"
                text={item.homeworkInstruction}
              />
            )}
            {item.homeworkStatus && previousHomework && (
              <LabeledReportSection
                icon="check"
                title="지난 첨삭과제 검사"
                rows={[
                  { label: "지난 과제", value: previousHomework },
                  {
                    label: "결과",
                    value: correctionHomeworkLabel(item.homeworkStatus),
                    tone: item.homeworkStatus,
                  },
                  item.homeworkNote
                    ? { label: "피드백", value: item.homeworkNote }
                    : null,
                ]}
              />
            )}
            {item.nextPreparation.trim() && (
              <ReportSection
                icon="notice"
                title="다음 준비"
                text={item.nextPreparation}
              />
            )}
          </div>
          {trendOpen && <ExamTrendModal supabase={supabase} studentId={studentId} initialSubject={item.subject} onClose={() => setTrendOpen(false)} />}
          {item.assistantFeedback.trim() && (
            <section className="family-teacher-feedback">
              <span className="family-teacher-feedback-icon">
                <HansalmaeIcon name="chat" size={19} />
              </span>
              <div>
                <b>{familyTeacherName(item.recordedByName)} 한마디</b>
                <p>
                  <span>{item.assistantFeedback}</span>
                </p>
              </div>
            </section>
          )}
        </div>
      </section>
    </div>
  );
}

function ReportCard({
  item,
  readAt,
  readTracking,
  onOpen,
}: {
  item: Report;
  readAt: string | null;
  readTracking: boolean;
  onOpen: () => void;
}) {
  const unreadAttention = useUnreadAttention(readTracking && !readAt);
  const attendance = item.attendance;
  const firstExam = item.exams[0] ?? null;
  const displayTitle = reportDisplayTitle(item);
  const examSummary = firstExam
    ? firstExam.score === null
      ? firstExam.examTitle || "시험 평가"
      : `${firstExam.examTitle || "시험"} ${formatRawExamScore(firstExam.score, firstExam.maxScore, isWordExam(`${firstExam.examTitle} ${firstExam.examType}`), false)}`
    : item.examContent;
  const assignmentSummary =
    item.homeworkContent ||
    (item.homeworkResult
      ? homeworkLabel[item.homeworkResult.status] ?? item.homeworkResult.status
      : "");
  return (
    <article
      ref={unreadAttention.ref}
      className={`family-report-card ${readTracking && !readAt ? "unread" : ""} ${unreadAttention.visible ? "attention-visible" : ""}`}
    >
      <button
        type="button"
        className="family-report-card-main"
        onClick={onOpen}
        aria-label={`${displayTitle} 리포트 자세히 보기`}
      >
        <span className="family-report-subject">
          <span className="family-report-card-title-row">
            <strong>{displayTitle}</strong>
            <span className="family-report-card-labels">
              <span>{reportBadgeLabel(item)}</span>
              {readTracking && !readAt && <em>NEW</em>}
            </span>
          </span>
          <small>
            {formatTime(item.startsAt)} · {familyTeacherName(item.teacherName)}
            {item.room ? ` · ${item.room}` : ""}
          </small>
          <FeedSummary
            lesson={item.lessonContent}
            exam={examSummary}
            assignment={assignmentSummary}
          />
        </span>
        {attendance && (
          <strong className={`family-attendance-badge ${attendance.status}`}>
            {attendanceLabel[attendance.status] ?? attendance.status}
            {attendance.status === "late" && attendance.lateMinutes
              ? ` ${attendance.lateMinutes}분`
              : ""}
          </strong>
        )}
        <span className="family-report-open">
          자세히 보기 <b>›</b>
        </span>
      </button>
    </article>
  );
}

function FeedSummary({
  lessonLabel = "수업내용",
  lesson,
  exam,
  assignment,
}: {
  lessonLabel?: string;
  lesson: string;
  exam: string;
  assignment: string;
}) {
  const rows = [
    [lessonLabel, lesson],
    ["시험", exam],
    ["과제", assignment],
  ].filter((row) => row[1]?.trim());
  if (!rows.length)
    return (
      <div className="family-report-card-summary empty">
        <p>수업 기록이 도착했어요.</p>
      </div>
    );
  return (
    <div className="family-report-card-summary">
      {rows.map(([label, value]) => (
        <p key={label}>
          <b>{label}</b>
          <span>{value}</span>
        </p>
      ))}
    </div>
  );
}

function ReportDetail({
  supabase,
  studentId,
  item,
  previousHomework,
  canComment,
  onClose,
}: {
  supabase: SupabaseClient;
  studentId: string;
  item: Report;
  previousHomework: string;
  canComment: boolean;
  onClose: () => void;
}) {
  useFamilyModalScrollLock();
  const [trendOpen, setTrendOpen] = useState(false);
  const attendance = item.attendance;
  const displayTitle = reportDisplayTitle(item);
  const attendanceMemo = [attendance?.absenceReason, attendance?.note]
    .filter(Boolean)
    .join(" · ");
  const displayExams = item.exams.filter(
    (exam) =>
      Boolean(exam.examTitle.trim()) ||
      Boolean(exam.examType.trim()) ||
      exam.score !== null ||
      Boolean(exam.feedback.trim()) ||
      Boolean(exam.evaluation.trim()),
  );
  const teacherFeedbacks = displayExams
    .filter((exam) => exam.feedback.trim())
    .map((exam) => ({
      label: exam.examTitle || exam.examType || "시험",
      text: exam.feedback.trim(),
    }));
  return (
    <div
      className="family-report-detail-backdrop"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <section
        className={`family-report-detail${trendOpen ? " trend-open" : ""}`}
        role="dialog"
        aria-modal="true"
        aria-labelledby="family-report-detail-title"
      >
        <header className="family-report-detail-head">
          <button type="button" onClick={onClose} aria-label="상세 리포트 닫기">
            ‹
          </button>
          <div>
            <small>{formatFullDate(item.lessonDate)}</small>
            <h2 id="family-report-detail-title">수업 상세 리포트</h2>
          </div>
          <span />
        </header>
        <div className="family-report-detail-scroll">
          <section className="family-report-detail-hero">
            <div className="family-report-card-labels">
              <span>{reportBadgeLabel(item)}</span>
            </div>
            <div>
              <h3>{displayTitle}</h3>
              {attendance && (
                <strong
                  className={`family-attendance-badge ${attendance.status}`}
                >
                  {attendanceLabel[attendance.status] ?? attendance.status}
                  {attendance.status === "late" && attendance.lateMinutes
                    ? ` ${attendance.lateMinutes}분`
                    : ""}
                </strong>
              )}
            </div>
            <p>
              {formatTime(item.startsAt)} ·{" "}
              {familyTeacherName(item.teacherName)}
              {item.room ? ` · ${item.room}` : ""}
            </p>
          </section>
          <div className="family-report-detail-sections">
            {item.lessonContent.trim() && (
              <ReportSection
                icon="book"
                title="오늘 수업"
                text={item.lessonContent}
              />
            )}
            {item.examContent.trim() && (
              <ReportSection
                icon="chart"
                title="오늘 시험·평가"
                text={item.examContent}
              />
            )}
            {displayExams.length > 0 && (
              <LabeledReportSection
                icon="chart"
                title="개인별 시험 결과"
                actionLabel="성적 추이 보기"
                onClick={() => setTrendOpen(true)}
                rows={displayExams.flatMap((exam) => {
                  const convertedScore = getConvertedScore(exam);
                  const rawScore =
                    exam.score !== null
                      ? formatRawExamScore(
                          exam.score,
                          exam.maxScore,
                          isWordExam(`${exam.examTitle} ${exam.examType}`),
                        )
                      : "";
                  return [
                    {
                      label: "시험",
                      value: exam.examTitle || exam.examType || "시험",
                    },
                    rawScore
                      ? {
                          label: "점수",
                          value:
                            convertedScore !== null
                              ? `${rawScore} (${Math.round(convertedScore)}점)`
                              : rawScore,
                        }
                      : null,
                    exam.feedback || exam.evaluation
                      ? {
                          label: "피드백",
                          value: exam.feedback || exam.evaluation,
                        }
                      : null,
                  ];
                })}
              />
            )}
            {item.homeworkResult && previousHomework && (
              <LabeledReportSection
                icon="check"
                title="지난 숙제 검사"
                rows={[
                  { label: "지난 숙제", value: previousHomework },
                  {
                    label: "결과",
                    value:
                      homeworkLabel[item.homeworkResult.status] ??
                      item.homeworkResult.status,
                    tone: item.homeworkResult.status,
                  },
                  item.homeworkResult.note
                    ? { label: "피드백", value: item.homeworkResult.note }
                    : null,
                ]}
              />
            )}
            {item.homeworkContent.trim() && (
              <ReportSection
                icon="edit"
                title="과제 및 복습"
                text={item.homeworkContent}
              />
            )}
            {attendanceMemo && (
              <ReportSection
                icon="notice"
                title="출결 메모"
                text={attendanceMemo}
              />
            )}
          </div>
          {trendOpen && <ExamTrendModal supabase={supabase} studentId={studentId} initialSubject={item.mainSubject || item.subject} onClose={() => setTrendOpen(false)} />}
          {teacherFeedbacks.length > 0 && (
            <section className="family-teacher-feedback">
              <span className="family-teacher-feedback-icon">
                <HansalmaeIcon name="chat" size={19} />
              </span>
              <div>
                <b>{familyTeacherName(item.teacherName)} 한마디</b>
                {teacherFeedbacks.map((feedback, index) => (
                  <p key={`${feedback.label}-${index}`}>
                    <strong>{feedback.label}</strong>
                    <span>{feedback.text}</span>
                  </p>
                ))}
              </div>
            </section>
          )}
          {canComment && (
            <FamilyReportComments
              supabase={supabase}
              studentId={studentId}
              lessonId={item.lessonId}
              teacherName={item.teacherName}
            />
          )}
        </div>
      </section>
    </div>
  );
}

function FamilyReportComments({
  supabase,
  studentId,
  lessonId,
  teacherName,
}: {
  supabase: SupabaseClient;
  studentId: string;
  lessonId: string;
  teacherName: string;
}) {
  const [items, setItems] = useState<ReportComment[]>([]);
  const [body, setBody] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [deleting, setDeleting] = useState<string | null>(null);
  const [error, setError] = useState("");
  const { reactions, reacting, load: loadReactions, toggle } =
    useReportCommentReactions(supabase);
  const load = useCallback(async (background = false) => {
    if (!background) setLoading(true);
    const { data, error: nextError } = await supabase.rpc(
      "family_report_comments",
      { p_student_id: studentId, p_lesson_id: lessonId },
    );
    if (nextError) {
      if (!background) setItems([]);
    } else {
      const nextItems = (data ?? []) as ReportComment[];
      setItems((current) =>
        JSON.stringify(current) === JSON.stringify(nextItems) ? current : nextItems,
      );
      await loadReactions(
        nextItems.filter((item) => !item.isDeleted).map((item) => item.id),
      );
    }
    setError(nextError ? "댓글을 불러오지 못했습니다." : "");
    if (!background) setLoading(false);
  }, [lessonId, loadReactions, studentId, supabase]);
  useEffect(() => {
    void Promise.resolve().then(() => load());
  }, [load]);
  useEffect(() => {
    const refresh = () => {
      if (document.visibilityState === "visible") void load(true);
    };
    const intervalId = window.setInterval(refresh, 5000);
    window.addEventListener("focus", refresh);
    document.addEventListener("visibilitychange", refresh);
    return () => {
      window.clearInterval(intervalId);
      window.removeEventListener("focus", refresh);
      document.removeEventListener("visibilitychange", refresh);
    };
  }, [load]);
  async function submit() {
    const next = body.trim();
    if (!next || saving) return;
    setSaving(true);
    setError("");
    const { error: nextError } = await supabase.rpc(
      "family_add_report_comment",
      { p_student_id: studentId, p_lesson_id: lessonId, p_body: next },
    );
    if (nextError) setError("댓글을 등록하지 못했습니다.");
    else {
      setBody("");
      await load(true);
    }
    setSaving(false);
  }
  async function remove(item: ReportComment) {
    if (
      deleting ||
      !item.canDelete ||
      !(await appConfirm({
        eyebrow: "댓글 삭제",
        title: "작성한 댓글을 삭제할까요?",
        notice: "선생님이 남긴 답변은 그대로 유지됩니다.",
        confirmLabel: "댓글 삭제",
        tone: "danger",
      }))
    )
      return;
    setDeleting(item.id);
    setError("");
    const { error: nextError } = await supabase.rpc("delete_report_comment", {
      p_comment_id: item.id,
    });
    if (nextError) setError("댓글을 삭제하지 못했습니다.");
    else await load(true);
    setDeleting(null);
  }
  const roots = items.filter((item) => !item.parentId);
  return (
    <section className="family-report-comments">
      <header>
        <div className="family-comment-heading-icon">
          <HansalmaeIcon name="chat" size={18} />
        </div>
        <span>
          <b>선생님과 댓글</b>
          <small>
            {familyTeacherName(teacherName)}와 수업에 대해 이야기해 보세요.
          </small>
        </span>
        <em>{items.length ? `${items.length}개` : "새 대화"}</em>
      </header>
      {loading ? (
        <p className="family-comment-empty">댓글을 불러오는 중이에요…</p>
      ) : roots.length ? (
        <div className="family-comment-list">
          {roots.map((root) => (
            <article key={root.id}>
              <div className="family-comment-message family-comment-message-parent">
                <time>{formatCommentTime(root.createdAt)}</time>
                <div
                  className={`family-comment-bubble ${root.isDeleted ? "deleted" : ""}`}
                >
                  <p>{root.body}</p>
                </div>
              </div>
              <div className="family-comment-action-row family-comment-action-parent">
                  <CommentReactionBar
                    commentId={root.id}
                    items={reactions[root.id] ?? []}
                    disabled={root.isDeleted}
                    reacting={reacting === root.id}
                    onToggle={(commentId, type) => void toggle(commentId, type)}
                  />
                  {root.canDelete && (
                    <button
                      type="button"
                      className="report-comment-delete"
                      disabled={deleting === root.id}
                      onClick={() => void remove(root)}
                    >
                      {deleting === root.id ? "삭제 중…" : "삭제"}
                    </button>
                  )}
              </div>
              {items
                .filter((reply) => reply.parentId === root.id)
                .map((reply) => (
                  <section className="family-comment-reply" key={reply.id}>
                    <div className="family-comment-reply-author">
                      <b>{familyTeacherName(reply.authorName)}</b>
                    </div>
                    <div className="family-comment-message family-comment-message-reply">
                      <div className={`family-comment-bubble ${reply.isDeleted ? "deleted" : ""}`}>
                        <p>{reply.body}</p>
                      </div>
                      <time>{formatCommentTime(reply.createdAt)}</time>
                    </div>
                    <div className="family-comment-action-row family-comment-action-reply">
                      <CommentReactionBar
                        commentId={reply.id}
                        items={reactions[reply.id] ?? []}
                        disabled={reply.isDeleted}
                        reacting={reacting === reply.id}
                        onToggle={(commentId, type) => void toggle(commentId, type)}
                      />
                    </div>
                  </section>
                ))}
            </article>
          ))}
        </div>
      ) : (
        <p className="family-comment-empty">
          아직 댓글이 없어요.
          <small>수업에 관해 궁금한 점을 편하게 남겨주세요.</small>
        </p>
      )}
      <div className="family-comment-compose">
        <textarea
          maxLength={500}
          rows={2}
          value={body}
          onChange={(event) => setBody(event.target.value)}
          placeholder="선생님께 전할 댓글을 입력하세요"
        />
        <footer>
          <span>{body.length}/500</span>
          <button
            type="button"
            disabled={!body.trim() || saving}
            onClick={() => void submit()}
          >
            {saving ? "등록 중…" : "댓글 등록"}
          </button>
        </footer>
      </div>
      {error && <p className="family-comment-error">{error}</p>}
    </section>
  );
}

function ReportSection({
  icon,
  title,
  text,
}: {
  icon: "book" | "edit" | "notice" | "chart" | "check";
  title: string;
  text: string;
}) {
  return (
    <section className="family-report-section">
      <i>
        <HansalmaeIcon name={icon} size={18} />
      </i>
      <div>
        <b>{title}</b>
        <p>{text}</p>
      </div>
    </section>
  );
}
type ReportDetailRow = {
  label: string;
  value: string;
  tone?: string;
} | null;

function LabeledReportSection({
  icon,
  title,
  rows,
  actionLabel,
  onClick,
}: {
  icon: "book" | "edit" | "notice" | "chart" | "check";
  title: string;
  rows: ReportDetailRow[];
  actionLabel?: string;
  onClick?: () => void;
}) {
  const visibleRows = rows.filter(
    (row): row is Exclude<ReportDetailRow, null> => Boolean(row?.value.trim()),
  );
  return (
    <section className={`family-report-section${onClick ? " family-report-section-action" : ""}`}>
      <i>
        <HansalmaeIcon name={icon} size={18} />
      </i>
      <div>
        <b>{title}</b>
        <div className="family-report-detail-rows">
          {visibleRows.map((row, index) => (
            <p key={`${row.label}-${index}`} className={row.tone ?? ""}>
              <strong>{row.label}:</strong>
              <span>{row.value}</span>
            </p>
          ))}
        </div>
        {onClick && <button type="button" className="family-report-trend-open" onClick={onClick}>{actionLabel ?? "자세히 보기"}<span aria-hidden="true">›</span></button>}
      </div>
    </section>
  );
}

export function ExamTrendModal({supabase,studentId,initialSubject,onClose,embedded=false}:{supabase:SupabaseClient;studentId:string;initialSubject:string;onClose:()=>void;embedded?:boolean}) {
  useFamilyModalScrollLock(!embedded);
  const [items,setItems]=useState<ExamTrendItem[]>([]);
  const [loading,setLoading]=useState(true);
  const [error,setError]=useState("");
  const [subject,setSubject]=useState(initialSubject);
  const [category,setCategory]=useState("");
  const [range,setRange]=useState<ExamTrendRange>("recent");
  const [selectedId,setSelectedId]=useState<string | null>(null);
  const [selectedRecordId,setSelectedRecordId]=useState<string | null>(null);
  const [listOpen,setListOpen]=useState(false);
  useEffect(()=>{let active=true;setLoading(true);void Promise.all([
    supabase.rpc("family_exam_progress",{p_student_id:studentId}),
    supabase.rpc("family_correction_exam_progress",{p_student_id:studentId}),
  ]).then(([regular,correction])=>{if(!active)return;if(regular.error&&correction.error){setError("성적 기록을 불러오지 못했습니다.");setItems([]);}else{setItems([...((regular.data??[]) as ExamTrendItem[]),...((correction.data??[]) as ExamTrendItem[])]);setError("");}setLoading(false);});return()=>{active=false};},[studentId,supabase]);
  const subjects=useMemo(()=>Array.from(new Set(items.map((item)=>trendSubject(item)))).filter(Boolean),[items]);
  const selectedSubject=subjects.includes(subject)?subject:(subjects[0]??"");
  const subjectItems=useMemo(()=>items.filter((item)=>trendSubject(item)===selectedSubject&&item.percent!==null),[items,selectedSubject]);
  const categories=useMemo(()=>Array.from(new Set(subjectItems.map(trendCategory).filter(Boolean))),[subjectItems]);
  const selectedCategory=categories.includes(category)?category:(categories[0]??"");
  const categoryItems=useMemo(()=>subjectItems.filter((item)=>trendCategory(item)===selectedCategory).sort((a,b)=>a.lessonDate.localeCompare(b.lessonDate)),[subjectItems,selectedCategory]);
  const filteredItems=useMemo(()=>filterTrendItems(categoryItems,range),[categoryItems,range]);
  const trendRows=useMemo(()=>buildTrendPoints(filteredItems,range),[filteredItems,range]);
  const recent=filteredItems.at(-1)??null;
  const average=filteredItems.length?Math.round(filteredItems.reduce((sum,item)=>sum+Number(item.percent),0)/filteredItems.length):null;
  const best=filteredItems.length?Math.round(Math.max(...filteredItems.map((item)=>Number(item.percent)))):null;
  const selectedPoint=trendRows.find((item)=>item.id===selectedId)??trendRows.at(-1)??null;
  const selectedRecord=categoryItems.find((item)=>item.id===selectedRecordId)??null;
  const selectedPointIndex=selectedPoint?trendRows.findIndex((item)=>item.id===selectedPoint.id):-1;
  const selectedRecordIndex=selectedRecord?categoryItems.findIndex((item)=>item.id===selectedRecord.id):-1;
  const width=520,height=205,padX=34,padY=30;
  const domainMin=trendRows.length?Math.max(0,Math.floor((Math.min(...trendRows.map((item)=>item.percent))-10)/10)*10):0;
  const domainSize=Math.max(10,100-domainMin);
  const points=trendRows.map((item,index)=>({item,x:trendRows.length===1?width/2:padX+(index*(width-padX*2))/(trendRows.length-1),y:padY+((100-item.percent)*(height-padY*2))/domainSize}));
  const path=points.map((point,index)=>`${index?"L":"M"}${point.x},${point.y}`).join(" ");
  const averageY=average===null?height-padY:padY+((100-average)*(height-padY*2))/domainSize;
  const labelStep=Math.max(1,Math.ceil(trendRows.length/6));
  const displayDetail=selectedRecord??selectedPoint?.items.at(-1)??null;
  const selectPoint=(id:string)=>{setSelectedId(id);setSelectedRecordId(null);};
  const moveDetail=(direction:-1|1)=>{if(selectedRecord){const next=categoryItems[selectedRecordIndex+direction];if(next)setSelectedRecordId(next.id);return;}const next=trendRows[selectedPointIndex+direction];if(next)selectPoint(next.id);};
  const content=<section className="family-exam-trend-modal" role={embedded?undefined:"dialog"} aria-modal={embedded?undefined:true} aria-labelledby="family-exam-trend-title">
      <header><button type="button" onClick={onClose} aria-label="성적 추이 닫기">‹</button><div><small>과목별 · 항목별 성장 기록</small><h2 id="family-exam-trend-title">시험 성적 추이</h2></div><span /></header>
      <div className="family-exam-trend-scroll">
        {loading?<p className="family-exam-trend-state">성적 기록을 불러오는 중이에요…</p>:error?<p className="family-exam-trend-state error">{error}</p>:!subjects.length?<p className="family-exam-trend-state">아직 그래프로 볼 시험 점수가 없어요.</p>:<>
          <nav className="family-exam-trend-subjects" aria-label="과목 선택">{subjects.map((name)=><button type="button" key={name} className={selectedSubject===name?"active":""} onClick={()=>{setSubject(name);setCategory("");setSelectedId(null);setSelectedRecordId(null);setListOpen(false);}}>{name}</button>)}</nav>
          <div className="family-exam-trend-categories" role="group" aria-label="시험 항목 선택">{categories.map((name)=><button type="button" key={name} className={selectedCategory===name?"active":""} onClick={()=>{setCategory(name);setSelectedId(null);setSelectedRecordId(null);setListOpen(false);}}>{name}</button>)}</div>
          <div className="family-exam-trend-ranges" role="group" aria-label="조회 기간">{([['recent','최근 10회'],['3m','3개월'],['6m','6개월'],['all','전체']] as const).map(([value,label])=><button type="button" key={value} className={range===value?"active":""} onClick={()=>{setRange(value);setSelectedId(null);setSelectedRecordId(null);setListOpen(false);}}>{label}</button>)}</div>
          <div className="family-exam-trend-summary"><span><small>최근 점수</small><b>{formatTrendScore(recent?.percent)}</b></span><span><small>{range==='recent'?'최근 평균':'기간 평균'}</small><b>{formatTrendScore(average)}</b></span><span><small>최고 점수</small><b>{formatTrendScore(best)}</b></span></div>
          {trendRows.length?<section className="family-exam-line-card"><div className="family-exam-chart-caption"><span>{range==='recent'?'개별 시험 점수':range==='all'?'월별 평균':'주별 평균'}</span><em><i />평균 {formatTrendScore(average)}</em></div><div className="family-exam-line-y"><span>100</span><span>{Math.round((100+domainMin)/2)}</span><span>{domainMin}</span></div><div className="family-exam-line-wrap"><svg viewBox={`0 0 ${width} ${height}`} role="img" aria-label={`${selectedSubject} ${selectedCategory} 점수 추이`} preserveAspectRatio="none"><defs><linearGradient id="familyExamArea" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#a12d66" stopOpacity=".25"/><stop offset="72%" stopColor="#c35b8d" stopOpacity=".07"/><stop offset="100%" stopColor="#fff" stopOpacity="0"/></linearGradient><filter id="familyExamGlow"><feGaussianBlur stdDeviation="4" result="blur"/><feMerge><feMergeNode in="blur"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs><line className="average" x1={padX} x2={width-padX} y1={averageY} y2={averageY}/><path className="area" d={`${path} L${points.at(-1)?.x},${height-padY} L${points[0]?.x},${height-padY} Z`}/><path className="line-shadow" d={path}/><path className="line" d={path}/>{points.map((point)=><g key={point.item.id} className={selectedPoint?.id===point.item.id?'selected':''}><circle className="halo" cx={point.x} cy={point.y} r="11"/><circle className="dot" cx={point.x} cy={point.y} r={selectedPoint?.id===point.item.id?6.5:4.5}/></g>)}</svg><div className="family-exam-line-points">{points.map((point)=><button type="button" key={point.item.id} style={{left:`${(point.x/width)*100}%`,top:`${(point.y/height)*100}%`}} aria-label={`${point.item.label} ${formatTrendScore(point.item.percent)}`} onClick={()=>selectPoint(point.item.id)} />)}</div><div className="family-exam-line-dates">{trendRows.map((item,index)=>(index%labelStep===0||index===trendRows.length-1)?<span key={item.id} style={{left:`${(points[index].x/width)*100}%`}}>{item.label}</span>:null)}</div></div></section>:<p className="family-exam-trend-state compact">선택한 기간의 점수 기록이 없어요.</p>}
          {(selectedPoint||selectedRecord)&&displayDetail&&<article className="family-exam-point-detail"><button type="button" className="previous" disabled={selectedRecord?selectedRecordIndex<=0:selectedPointIndex<=0} onClick={()=>moveDetail(-1)} aria-label="이전 기록">‹</button><div><small>{selectedRecord?formatFullDate(displayDetail.lessonDate):selectedPoint!.items.length>1?`${selectedPoint!.label} · ${selectedPoint!.items.length}회 평균`:formatFullDate(displayDetail.lessonDate)}</small><b>{selectedRecord||selectedPoint!.items.length===1?displayDetail.examTitle||trendCategory(displayDetail):`${selectedCategory} 평균`}</b><span>{selectedRecord||selectedPoint!.items.length===1?`${displayDetail.className} · ${trendSourceLabel(displayDetail.itemType)}`:`${selectedPoint!.items.length}개 시험 기록을 묶어 표시`}</span></div><strong>{selectedRecord||selectedPoint!.items.length===1?formatRawExamScore(Number(displayDetail.score),Number(displayDetail.maxScore),isWordExam(`${displayDetail.examTitle} ${displayDetail.examType}`)):formatTrendScore(selectedPoint!.percent)}<small>{selectedRecord||selectedPoint!.items.length===1?`${formatTrendScore(displayDetail.percent)} 환산`:"기간 평균"}</small></strong><button type="button" className="next" disabled={selectedRecord?selectedRecordIndex<0||selectedRecordIndex>=categoryItems.length-1:selectedPointIndex<0||selectedPointIndex>=trendRows.length-1} onClick={()=>moveDetail(1)} aria-label="다음 기록">›</button></article>}
          <button type="button" className={`family-exam-history-toggle${listOpen?' open':''}`} onClick={()=>setListOpen((value)=>!value)}><span>전체 기록 보기 <b>{categoryItems.length}</b></span><i>{listOpen?'접기':'펼치기'} <em>⌄</em></i></button>
          {listOpen&&<div className="family-exam-history-list">{[...categoryItems].reverse().map((item)=><button type="button" key={item.id} className={selectedRecordId===item.id?'active':''} onClick={()=>{setSelectedRecordId(item.id);setSelectedId(null);}}><time>{shortTrendDate(item.lessonDate)}</time><span><b>{item.examTitle||trendCategory(item)}</b><small>{item.className} · {trendSourceLabel(item.itemType)}</small></span><strong>{formatTrendScore(item.percent)}</strong></button>)}</div>}
        </>}
      </div>
    </section>;
  if(embedded)return <div className="family-exam-trend-embedded">{content}</div>;
  return <div className="family-exam-trend-backdrop" onMouseDown={(event)=>{event.stopPropagation();if(event.target===event.currentTarget)onClose();}}>{content}</div>;
}
function filterTrendItems(items:ExamTrendItem[],range:ExamTrendRange){if(range==='recent')return items.slice(-10);if(range==='all')return items;const months=range==='3m'?3:6;const cutoff=dateValue(koreaDate());cutoff.setMonth(cutoff.getMonth()-months);return items.filter((item)=>dateValue(item.lessonDate)>=cutoff);}
function buildTrendPoints(items:ExamTrendItem[],range:ExamTrendRange):ExamTrendPoint[]{if(range==='recent')return items.map((item)=>({id:item.id,label:shortTrendDate(item.lessonDate),lessonDate:item.lessonDate,percent:Math.round(Number(item.percent)),items:[item]}));const groups=new Map<string,ExamTrendItem[]>();for(const item of items){const key=range==='all'?item.lessonDate.slice(0,7):trendWeekKey(item.lessonDate);groups.set(key,[...(groups.get(key)??[]),item]);}return Array.from(groups.entries()).map(([key,group])=>({id:`${range}-${key}`,label:range==='all'?`${key.slice(2,4)}.${Number(key.slice(5))}`:shortTrendDate(group[0].lessonDate),lessonDate:group.at(-1)?.lessonDate??group[0].lessonDate,percent:Math.round(group.reduce((sum,item)=>sum+Number(item.percent),0)/group.length),items:group}));}
function trendWeekKey(value:string){const date=dateValue(value);const day=(date.getDay()+6)%7;date.setDate(date.getDate()-day);return `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}`;}
function trendSubject(item:ExamTrendItem){return (item.mainSubject||item.subject||"기타").trim();}
function trendCategory(item:ExamTrendItem){return (item.examType||item.examTitle||"기타 시험").trim();}
function trendSourceLabel(value:ExamTrendItem["itemType"]){return value==="makeup"?"보강수업":value==="extra"?"추가수업":value==="correction"?"첨삭수업":"정규수업";}
function formatTrendScore(value:number|null|undefined){return value==null?"–":`${Math.round(Number(value))}점`;}
function shortTrendDate(value:string){const date=dateValue(value);return `${date.getMonth()+1}.${date.getDate()}`;}
function withSubjectParticle(value:string){const name=value.trim();const last=[...name].at(-1)??"";const hangulIndex=last.charCodeAt(0)-0xac00;return `${name}${hangulIndex>=0&&hangulIndex<=11171&&hangulIndex%28!==0?"이":"가"}`;}
function dateValue(value: string) {
  return new Date(`${value}T12:00:00+09:00`);
}
function formatDateTitle(value: string) {
  return new Intl.DateTimeFormat("ko-KR", {
    timeZone: "Asia/Seoul",
    month: "long",
    day: "numeric",
  }).format(dateValue(value));
}
function formatDateWeekday(value: string) {
  return new Intl.DateTimeFormat("ko-KR", {
    timeZone: "Asia/Seoul",
    weekday: "long",
  }).format(dateValue(value));
}
function formatFullDate(value: string) {
  return new Intl.DateTimeFormat("ko-KR", {
    timeZone: "Asia/Seoul",
    year: "numeric",
    month: "long",
    day: "numeric",
    weekday: "long",
  }).format(dateValue(value));
}
function formatTime(value: string) {
  return new Intl.DateTimeFormat("ko-KR", {
    timeZone: "Asia/Seoul",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(new Date(value));
}
function formatScore(value: number) {
  return Number.isInteger(Number(value))
    ? String(Number(value))
    : Number(value).toFixed(1);
}
function isWordExam(value: string) {
  return /단어|voca|vocabulary/i.test(value ?? "");
}
function formatRawExamScore(
  score: number,
  maxScore: number,
  useCountUnit: boolean,
  spaced = true,
) {
  const separator = spaced ? " / " : "/";
  const unit = useCountUnit ? "개" : "";
  return `${formatScore(score)}${unit}${separator}${formatScore(maxScore)}${unit}`;
}
function getConvertedScore(exam: Exam) {
  if (exam.score === null) return null;
  if (exam.percent !== null && Number.isFinite(Number(exam.percent)))
    return Math.round(Number(exam.percent) * 10) / 10;
  if (!Number.isFinite(Number(exam.maxScore)) || Number(exam.maxScore) <= 0)
    return null;
  return Math.round((Number(exam.score) / Number(exam.maxScore)) * 1000) / 10;
}
function findPreviousLessonHomework(current: Report, reports: Report[]) {
  return (
    reports
      .filter(
        (report) =>
          report.classId === current.classId &&
          report.startsAt < current.startsAt &&
          report.homeworkContent.trim(),
      )
      .sort((left, right) => right.startsAt.localeCompare(left.startsAt))[0]
      ?.homeworkContent.trim() ?? ""
  );
}
function findPreviousCorrectionHomework(
  current: CorrectionReport,
  reports: CorrectionReport[],
) {
  const currentTime = `${current.correctionDate}T${current.startTime}`;
  return (
    reports
      .filter(
        (report) =>
          report.subject === current.subject &&
          `${report.correctionDate}T${report.startTime}` < currentTime &&
          report.homeworkInstruction.trim(),
      )
      .sort((left, right) =>
        `${right.correctionDate}T${right.startTime}`.localeCompare(
          `${left.correctionDate}T${left.startTime}`,
        ),
      )[0]?.homeworkInstruction.trim() ?? ""
  );
}
function formatCommentTime(value: string) {
  return new Intl.DateTimeFormat("ko-KR", {
    timeZone: "Asia/Seoul",
    month: "numeric",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  }).format(new Date(value));
}
function cleanCorrectionRange(value: string) {
  return (value ?? "").replace(/^\[종류\][^\n]*\n?/, "").trim();
}
function normalizeCorrectionReport(report: CorrectionReport): CorrectionReport {
  return {
    ...report,
    correctionDate: report.correctionDate ?? "",
    startTime: report.startTime ?? "",
    endTime: report.endTime ?? "",
    subject: report.subject ?? "첨삭",
    attendanceStatus: report.attendanceStatus ?? "scheduled",
    examTitle: report.examTitle ?? "",
    examRange: report.examRange ?? "",
    evaluation: report.evaluation ?? "",
    homeworkInstruction: report.homeworkInstruction ?? "",
    homeworkNote: report.homeworkNote ?? "",
    correctionContent: report.correctionContent ?? "",
    assistantFeedback: report.assistantFeedback ?? "",
    nextPreparation: report.nextPreparation ?? "",
  };
}
function reportDisplayTitle(item: Report) {
  if (
    item.mainSubject &&
    (item.subject === "보강" || item.subject === "추가수업")
  )
    return `${item.mainSubject} ${item.subject}`;
  return item.className;
}
function reportBadgeLabel(item: Report) {
  return item.mainSubject &&
    (item.subject === "보강" || item.subject === "추가수업")
    ? `${item.mainSubject} ${item.subject}`
    : item.subject;
}
function correctionHomeworkLabel(value: string) {
  return (
    {
      complete: "완료",
      partial: "일부 완료",
      missing: "미제출",
      excused: "확인 제외",
    }[value] ?? value
  );
}

function useUnreadAttention(enabled: boolean) {
  const [visible, setVisible] = useState(false);
  const observer = useRef<IntersectionObserver | null>(null);
  const ref = useCallback(
    (node: HTMLElement | null) => {
      observer.current?.disconnect();
      observer.current = null;
      if (!enabled || !node) {
        setVisible(false);
        return;
      }
      observer.current = new IntersectionObserver(
        ([entry]) => setVisible(entry.isIntersecting),
        { threshold: 0.45 },
      );
      observer.current.observe(node);
    },
    [enabled],
  );
  useEffect(() => () => observer.current?.disconnect(), []);
  return { ref, visible };
}
