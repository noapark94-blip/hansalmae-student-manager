"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { HansalmaeIcon } from "./hansalmae-icons";
import { appConfirm } from "./app-dialog";
import { familyTeacherName } from "./family-teacher-name";
import {
  CommentReactionBar,
  useReportCommentReactions,
} from "./report-comment-reactions";

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

export function FamilyLearningReportFeed({
  supabase,
  studentId,
  studentName,
}: {
  supabase: SupabaseClient;
  studentId: string;
  studentName?: string;
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
          <span>오늘 무엇을 배우고 어떻게 해냈는지 확인하세요.</span>
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
                      onOpen={() => setSelected(item)}
                    />
                  ) : (
                    <CorrectionFeedCard
                      key={`correction-${item.report.id}`}
                      item={item.report}
                      readAt={correctionReads[item.report.id] ?? null}
                      onOpen={() => setSelected(item)}
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
          readAt={reads[selected.report.lessonId] ?? null}
          readTracking={readTracking}
          confirming={confirming === selected.report.lessonId}
          onClose={() => setSelected(null)}
          onConfirm={() => void confirmRead(selected.report.lessonId)}
        />
      )}
      {selected?.kind === "correction" && (
        <CorrectionFeedDetail
          item={selected.report}
          previousHomework={findPreviousCorrectionHomework(
            selected.report,
            corrections,
          )}
          readAt={correctionReads[selected.report.id] ?? null}
          confirming={confirming === selected.report.id}
          onClose={() => setSelected(null)}
          onConfirm={() => void confirmCorrectionRead(selected.report.id)}
        />
      )}
    </section>
  );
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
  item,
  previousHomework,
  readAt,
  confirming,
  onClose,
  onConfirm,
}: {
  item: CorrectionReport;
  previousHomework: string;
  readAt: string | null;
  confirming: boolean;
  onClose: () => void;
  onConfirm: () => void;
}) {
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
      <section className="family-report-detail" role="dialog" aria-modal="true">
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
        <footer className="family-report-confirm">
          <span>
            {readAt
              ? `확인 완료 · ${formatReadTime(readAt)}`
              : "내용을 확인했다면 표시를 남겨주세요."}
          </span>
          {!readAt && (
            <button type="button" disabled={confirming} onClick={onConfirm}>
              <HansalmaeIcon name="check" size={16} />
              {confirming ? "처리 중…" : "확인했어요"}
            </button>
          )}
        </footer>
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
  readAt,
  readTracking,
  confirming,
  onClose,
  onConfirm,
}: {
  supabase: SupabaseClient;
  studentId: string;
  item: Report;
  previousHomework: string;
  canComment: boolean;
  readAt: string | null;
  readTracking: boolean;
  confirming: boolean;
  onClose: () => void;
  onConfirm: () => void;
}) {
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
        className="family-report-detail"
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
        {readTracking && (
          <footer className="family-report-confirm">
            <span>
              {readAt
                ? `확인 완료 · ${formatReadTime(readAt)}`
                : "내용을 확인했다면 표시를 남겨주세요."}
            </span>
            {!readAt && (
              <button type="button" disabled={confirming} onClick={onConfirm}>
                <HansalmaeIcon name="check" size={16} />
                {confirming ? "처리 중…" : "확인했어요"}
              </button>
            )}
          </footer>
        )}
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
}: {
  icon: "book" | "edit" | "notice" | "chart" | "check";
  title: string;
  rows: ReportDetailRow[];
}) {
  const visibleRows = rows.filter(
    (row): row is Exclude<ReportDetailRow, null> => Boolean(row?.value.trim()),
  );
  return (
    <section className="family-report-section">
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
      </div>
    </section>
  );
}
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
function formatReadTime(value: string) {
  return new Intl.DateTimeFormat("ko-KR", {
    timeZone: "Asia/Seoul",
    month: "numeric",
    day: "numeric",
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
