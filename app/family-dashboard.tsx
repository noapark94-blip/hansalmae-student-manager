"use client";

import type { CSSProperties } from "react";
import { useCallback, useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Profile } from "./supabase";
import { FamilyLearningNote } from "./family-learning-note";
import { FamilyLearningReportFeed } from "./family-learning-report-feed";
import { FamilyExamGrowth } from "./family-exam-growth";
import { FamilyCorrectionExamGrowth } from "./family-correction-exam-growth";
import { HansalmaeIcon } from "./hansalmae-icons";
import { familyTeacherName, familyTeacherNames } from "./family-teacher-name";

type FamilyView =
  | "schedule"
  | "attendance"
  | "makeups"
  | "assignments"
  | "reports"
  | "consultations"
  | "communications"
  | "my-account";
type Child = {
  id: string;
  name: string;
  school: string | null;
  grade: string | null;
};
type ClassItem = {
  id: string;
  name: string;
  subject: string;
  room: string | null;
  color: string;
  weekday: number;
  startTime: string;
  endTime: string;
  teachers: string;
};
type Upcoming = {
  id: string;
  name: string;
  subject: string;
  room: string | null;
  color: string;
  classDate: string;
  startTime: string;
  teachers: string;
};
type Assignment = {
  id: string;
  title: string;
  className: string;
  dueAt: string;
  status: string;
  feedback: string | null;
};
type Attendance = {
  id: string;
  lessonDate: string;
  className: string;
  status: string;
  note: string | null;
};
type Makeup = {
  id: string;
  className: string;
  scheduledAt: string;
  room: string;
  status: string;
  teacherName: string;
};
type Announcement = {
  id: string;
  title: string;
  body: string;
  publishedAt: string;
  authorName: string;
};
type Consultation = {
  id: string;
  consultedAt: string;
  type: string;
  consultantName: string;
  summary: string;
  nextContactOn: string | null;
};
type ExamProgressItem = {
  id: string;
  lessonDate: string;
  className: string;
  subject: string;
  mainSubject: string;
  examTitle: string | null;
  score: number | null;
  maxScore: number;
  percent: number | null;
  evaluation: string | null;
  feedback: string | null;
  teacherName: string;
};
type Data = {
  role: "student" | "guardian";
  children: Child[];
  selectedStudent: Child | null;
  weekClasses: ClassItem[];
  upcomingClasses: Upcoming[];
  attendanceSummary: {
    total: number;
    present: number;
    late: number;
    absent: number;
  };
  recentAttendance: Attendance[];
  makeups: Makeup[];
  assignments: Assignment[];
  announcements: Announcement[];
  consultations: Consultation[];
};
const weekdays = ["월", "화", "수", "목", "금", "토"];
const weekdayNumbers: Record<string, number> = { Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 };
function seoulWeekday() {
  const day = new Intl.DateTimeFormat("en-US", { timeZone: "Asia/Seoul", weekday: "short" }).format(new Date());
  return weekdayNumbers[day] ?? 7;
}
const attendanceLabels: Record<string, string> = {
  present: "출석",
  late: "지각",
  absent: "결석",
  excused: "결석",
};
export function FamilyLiveDashboard({
  supabase,
  profile,
  onNavigate,
}: {
  supabase: SupabaseClient;
  profile: Profile;
  onNavigate: (view: FamilyView) => void;
}) {
  const [data, setData] = useState<Data | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const load = useCallback(
    async (id: string | null) => {
      setLoading(true);
      setError("");
      const { data: next, error: e } = await supabase.rpc(
        "family_live_dashboard",
        { p_student_id: id },
      );
      if (e) setError("학습 현황을 불러오지 못했습니다.");
      else {
        const parsed = next as Data;
        setData(parsed);
        setSelectedId(parsed.selectedStudent?.id ?? null);
      }
      setLoading(false);
    },
    [supabase],
  );
  useEffect(() => {
    void load(null);
  }, [load]);
  const selected = data?.selectedStudent;
  const rate = useMemo(
    () =>
      data?.attendanceSummary.total
        ? Math.round(
            (data.attendanceSummary.present / data.attendanceSummary.total) *
              100,
          )
        : null,
    [data],
  );
  if (loading && !data)
    return (
      <section className="panel hub-message">
        학습 현황을 불러오는 중이에요…
      </section>
    );
  if (error && !data)
    return <section className="panel hub-message error">{error}</section>;
  return (
    <div className="family-mobile-home">
      <section className="family-app-welcome">
        <p>
          {profile.role === "student"
            ? "오늘도 차근차근"
            : "자녀의 오늘을 확인하세요"}
        </p>
        <h1>
          {profile.role === "student"
            ? `안녕하세요, ${profile.display_name}님`
            : `${selected?.name ?? "자녀"}의 학습 공간`}
        </h1>
        <span>수업·출결·시험·숙제를 한곳에서 확인하세요.</span>
      </section>
      {error && <p className="attendance-error">{error}</p>}
      {!selected ? (
        <section className="panel family-empty">
          <b>연결된 학생 정보가 없습니다.</b>
        </section>
      ) : (
        <>
          <section className="family-profile-card">
            <div className="family-profile-avatar">
              {selected.name.slice(0, 1)}
            </div>
            <div>
              <b>{selected.name}</b>
              <span>
                {[selected.school, selected.grade]
                  .filter(Boolean)
                  .join(" · ") || "한살매 학생"}
              </span>
              <small>
                {profile.role === "guardian"
                  ? "학부모 계정으로 연결됨"
                  : "나의 학습 정보"}
              </small>
            </div>
            {profile.role === "guardian" && (data?.children.length ?? 0) > 1 ? (
              <label>
                <span>자녀 선택</span>
                <select
                  disabled={loading}
                  value={selectedId ?? ""}
                  onChange={(e) => void load(e.target.value)}
                >
                  {data?.children.map((c) => (
                    <option key={c.id} value={c.id}>
                      {c.name} · {[c.school, c.grade].filter(Boolean).join(" ")}
                    </option>
                  ))}
                </select>
              </label>
            ) : (
              <i aria-hidden="true">›</i>
            )}
          </section>
          <FamilyLearningNote
            studentName={selected.name}
            attendance={data?.recentAttendance ?? []}
            assignments={data?.assignments ?? []}
            announcements={data?.announcements ?? []}
            todayClassCount={(data?.weekClasses ?? []).filter((item) => item.weekday === seoulWeekday()).length}
            onNavigate={(view) =>
              onNavigate(view === "communications" ? "communications" : "reports")
            }
          />
          <FamilyLearningReportFeed
            supabase={supabase}
            studentId={selected.id}
          />
          <section className="stats-grid family-stats">
            <FamilyStat
              label="주간 수업"
              value={String(data?.weekClasses.length ?? 0)}
              unit="개"
              detail={
                data?.upcomingClasses[0]
                  ? `다음 ${formatUpcoming(data.upcomingClasses[0])}`
                  : "예정 수업 없음"
              }
              icon="calendar"
              tone="blue"
            />
            <FamilyStat
              label="이번 달 출석률"
              value={rate === null ? "–" : String(rate)}
              unit={rate === null ? "" : "%"}
              detail={`출석 ${data?.attendanceSummary.present ?? 0} · 지각 ${data?.attendanceSummary.late ?? 0} · 결석 ${data?.attendanceSummary.absent ?? 0}`}
              icon="check"
              tone="green"
            />
            <FamilyStat
              label="확인할 과제"
              value={String(
                data?.assignments.filter((x) => x.status !== "reviewed")
                  .length ?? 0,
              )}
              unit="건"
              detail="제출 전·첨삭 대기"
              icon="edit"
              tone="amber"
            />
            <FamilyStat
              label="예정 보강"
              value={String(
                data?.makeups.filter((x) => x.status === "scheduled").length ??
                  0,
              )}
              unit="건"
              detail="앞으로 진행할 보강"
              icon="refresh"
              tone="wine"
            />
          </section>
          <div className="family-score-trends">
            <div className="family-score-trend-label">
              <b>정규수업</b>
              <span>클래스에서 기록한 시험</span>
            </div>
            <FamilyExamGrowth supabase={supabase} studentId={selected.id} />
            <div className="family-score-trend-label correction">
              <b>첨삭수업</b>
              <span>첨삭 관리에서 기록한 시험</span>
            </div>
            <FamilyCorrectionExamGrowth
              supabase={supabase}
              studentId={selected.id}
            />
          </div>
          <FamilyExamProgress supabase={supabase} studentId={selected.id} />
          <div className="family-dashboard-grid">
            <section className="panel family-upcoming">
              <PanelTitle
                title="다가오는 수업"
                action="주간 시간표"
                onClick={() => onNavigate("schedule")}
              />
              {data?.upcomingClasses.length ? (
                <div>
                  {data.upcomingClasses.map((item) => (
                    <article key={`${item.id}-${item.classDate}`}>
                      <time>
                        {formatClassDate(item.classDate)}
                        <b>{item.startTime.slice(0, 5)}</b>
                      </time>
                      <i style={{ background: item.color }} />
                      <span>
                        <b>{item.name}</b>
                        <small>
                          {item.teachers
                            ? familyTeacherNames(item.teachers)
                            : "담당 선생님"}
                          {item.room ? ` · ${item.room}` : ""}
                        </small>
                      </span>
                    </article>
                  ))}
                </div>
              ) : (
                <Empty text="다가오는 수업이 없습니다." />
              )}
            </section>
            <section className="panel family-notices">
              <PanelTitle
                title="학원 공지"
                action="전체 공지"
                onClick={() => onNavigate("communications")}
              />
              {data?.announcements.length ? (
                <div>
                  {data.announcements.slice(0, 4).map((item) => (
                    <article key={item.id}>
                      <span>
                        <b>{item.title}</b>
                        <p>{item.body}</p>
                        <small>
                          {familyTeacherName(item.authorName)} · {formatDate(item.publishedAt)}
                        </small>
                      </span>
                    </article>
                  ))}
                </div>
              ) : (
                <Empty text="새로운 공지가 없습니다." />
              )}
            </section>
            <section className="panel family-week">
              <PanelTitle title="주간 시간표" />
              <div>
                {weekdays.map((day, index) => (
                  <section key={day}>
                    <b>{day}</b>
                    {data?.weekClasses
                      .filter((item) => item.weekday === index + 1)
                      .map((item) => (
                        <span key={item.id} style={{ borderColor: item.color }}>
                          <strong>{item.startTime.slice(0, 5)}</strong>
                          <em>{item.name}</em>
                          <small>{item.room || item.subject}</small>
                        </span>
                      ))}
                  </section>
                ))}
              </div>
            </section>
            <section className="panel family-progress">
              <PanelTitle title="최근 학습 현황" />
              <div className="family-progress-list">
                <ProgressButton
                  icon="check"
                  tone="green"
                  title="최근 출결"
                  meta={
                    data?.recentAttendance[0]
                      ? `${formatDate(data.recentAttendance[0].lessonDate)} · ${data.recentAttendance[0].className} · ${attendanceLabels[data.recentAttendance[0].status]}`
                      : "출결 기록 없음"
                  }
                  count={data?.recentAttendance.length ?? 0}
                  onClick={() => onNavigate("reports")}
                />
                <ProgressButton
                  icon="refresh"
                  tone="wine"
                  title="보강 일정"
                  meta={
                    data?.makeups[0]
                      ? `${formatDateTime(data.makeups[0].scheduledAt)} · ${data.makeups[0].className}`
                      : "예정된 보강 없음"
                  }
                  count={
                    data?.makeups.filter((x) => x.status === "scheduled")
                      .length ?? 0
                  }
                  onClick={() => onNavigate("schedule")}
                />
                <ProgressButton
                  icon="edit"
                  tone="amber"
                  title="과제·첨삭"
                  meta={
                    data?.assignments[0]
                      ? `${data.assignments[0].title} · ${assignmentLabel(data.assignments[0].status)}`
                      : "확인할 과제 없음"
                  }
                  count={
                    data?.assignments.filter((x) => x.status !== "reviewed")
                      .length ?? 0
                  }
                  onClick={() => onNavigate("reports")}
                />
                <ProgressButton
                  icon="chat"
                  tone="blue"
                  title="공개 상담 요약"
                  meta={
                    data?.consultations[0]
                      ? `${formatDate(data.consultations[0].consultedAt)} · ${data.consultations[0].summary}`
                      : "공개된 상담 요약 없음"
                  }
                  count={data?.consultations.length ?? 0}
                  onClick={() => onNavigate("consultations")}
                />
              </div>
            </section>
          </div>
        </>
      )}
    </div>
  );
}
export function FamilyScheduleView({ supabase, profile }: { supabase: SupabaseClient; profile: Profile }) {
  const [data, setData] = useState<Data | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const load = useCallback(async (studentId: string | null) => {
    setLoading(true);
    setError("");
    const { data: next, error: loadError } = await supabase.rpc("family_live_dashboard", { p_student_id: studentId });
    if (loadError || !next) setError("시간표를 불러오지 못했습니다.");
    else {
      const parsed = next as Data;
      setData(parsed);
      setSelectedId(parsed.selectedStudent?.id ?? null);
    }
    setLoading(false);
  }, [supabase]);
  useEffect(() => { void load(null); }, [load]);
  if (loading && !data) return <section className="panel hub-message">시간표를 불러오는 중이에요…</section>;
  if (error && !data) return <section className="panel hub-message error">{error}</section>;
  const selected = data?.selectedStudent;
  return <div className="family-schedule-page">
    <header className="family-schedule-heading">
      <p>{profile.role === "guardian" ? "자녀 일정" : "나의 일정"}</p>
      <h1>주간 시간표</h1>
      <span>정규수업과 예정된 수업 시간을 한눈에 확인하세요.</span>
    </header>
    {error && <p className="attendance-error">{error}</p>}
    {selected ? <>
      <section className="family-schedule-student">
        <i>{selected.name.slice(0, 1)}</i>
        <span><b>{selected.name}</b><small>{[selected.school, selected.grade].filter(Boolean).join(" · ") || "한살매 학생"}</small></span>
        {profile.role === "guardian" && (data?.children.length ?? 0) > 1 && <select aria-label="자녀 선택" disabled={loading} value={selectedId ?? ""} onChange={(event) => void load(event.target.value)}>{data?.children.map((child) => <option key={child.id} value={child.id}>{child.name}</option>)}</select>}
      </section>
      <section className="family-weekly-schedule" aria-label={`${selected.name} 주간 시간표`}>
        {weekdays.map((day, index) => {
          const classes = data?.weekClasses.filter((item) => item.weekday === index + 1) ?? [];
          return <article key={day} className={classes.length ? "has-class" : ""}>
            <header><b>{day}</b><span>{classes.length ? `${classes.length}개 수업` : "수업 없음"}</span></header>
            <div>{classes.length ? classes.map((item) => <section key={item.id} style={{ "--family-class-color": item.color } as CSSProperties}>
              <time>{item.startTime.slice(0, 5)}–{item.endTime.slice(0, 5)}</time>
              <span><b>{item.name}</b><small>{item.subject} · {familyTeacherNames(item.teachers)}{item.room ? ` · ${item.room}` : ""}</small></span>
            </section>) : <p>예정된 수업이 없습니다.</p>}</div>
          </article>;
        })}
      </section>
      <section className="family-schedule-note"><HansalmaeIcon name="notice" size={18}/><span><b>보강·추가수업·첨삭 안내</b><small>확정된 예정 일정은 시간표에서, 수업을 마치고 발행된 기록은 홈 학습 피드와 리포트에서 확인할 수 있어요.</small></span></section>
    </> : <section className="panel family-empty"><b>연결된 학생 정보가 없습니다.</b></section>}
  </div>;
}
function FamilyExamProgress({
  supabase,
  studentId,
}: {
  supabase: SupabaseClient;
  studentId: string;
}) {
  const [items, setItems] = useState<ExamProgressItem[]>([]);
  const [subject, setSubject] = useState("");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  useEffect(() => {
    let active = true;
    setLoading(true);
    void supabase
      .rpc("family_exam_progress", { p_student_id: studentId })
      .then(({ data, error: e }) => {
        if (!active) return;
        if (e) setError("시험 성적을 불러오지 못했습니다.");
        else setItems((data ?? []) as ExamProgressItem[]);
        setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [studentId, supabase]);
  const subjects = useMemo(
    () => Array.from(new Set(items.map((x) => x.subject))),
    [items],
  );
  const selected =
    subject && subjects.includes(subject) ? subject : (subjects[0] ?? "");
  const rows = items.filter((x) => x.subject === selected).slice(0, 5);
  return (
    <section className="panel family-exam-progress">
      <header>
        <div>
          <p className="eyebrow">정규수업 시험 기록</p>
          <h2>시험 성적·선생님 피드백</h2>
        </div>
        {subjects.length > 0 && (
          <nav>
            {subjects.map((x) => (
              <button
                key={x}
                className={selected === x ? "active" : ""}
                onClick={() => setSubject(x)}
              >
                {x}
              </button>
            ))}
          </nav>
        )}
      </header>
      {loading ? (
        <Empty text="시험 기록을 불러오는 중이에요…" />
      ) : error ? (
        <p className="family-exam-error">{error}</p>
      ) : !items.length ? (
        <Empty text="아직 등록된 시험 결과가 없습니다." />
      ) : (
        <div className="family-exam-records">
          {rows.map((item) => (
            <article key={item.id}>
              <time>{formatDate(item.lessonDate)}</time>
              <span>
                <b>{item.examTitle || `${item.className} 시험`}</b>
                <small>
                  {item.className} · {familyTeacherName(item.teacherName)}
                </small>
                {item.evaluation && <em>{item.evaluation}</em>}
                {item.feedback && <p>{item.feedback}</p>}
              </span>
              <strong>
                {item.score === null ? "평가" : formatScore(item.score)}
                <small>
                  {item.score === null
                    ? "점수 미입력"
                    : ` / ${formatScore(item.maxScore)}점`}
                </small>
              </strong>
            </article>
          ))}
        </div>
      )}
    </section>
  );
}
function FamilyStat({
  label,
  value,
  unit,
  detail,
  icon,
  tone,
}: {
  label: string;
  value: string;
  unit: string;
  detail: string;
  icon: "calendar" | "check" | "edit" | "refresh";
  tone: string;
}) {
  return (
    <article className="stat-card">
      <span className={`stat-icon ${tone}`}>
        <HansalmaeIcon name={icon} size={21} />
      </span>
      <div>
        <span>{label}</span>
        <strong>
          {value}
          <i>{unit}</i>
        </strong>
        <small>{detail}</small>
      </div>
    </article>
  );
}
function ProgressButton({
  icon,
  tone,
  title,
  meta,
  count,
  onClick,
}: {
  icon: "check" | "refresh" | "edit" | "chat";
  tone: string;
  title: string;
  meta: string;
  count: number;
  onClick: () => void;
}) {
  return (
    <button onClick={onClick}>
      <i className={tone}>
        <HansalmaeIcon name={icon} size={19} />
      </i>
      <span>
        <b>{title}</b>
        <small>{meta}</small>
      </span>
      <strong>{count}</strong>
    </button>
  );
}
function PanelTitle({
  title,
  action,
  onClick,
}: {
  title: string;
  action?: string;
  onClick?: () => void;
}) {
  return (
    <header>
      <h2>{title}</h2>
      {action && <button onClick={onClick}>{action} ›</button>}
    </header>
  );
}
function Empty({ text }: { text: string }) {
  return <p className="family-list-empty">{text}</p>;
}
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
function formatClassDate(value: string) {
  return new Intl.DateTimeFormat("ko-KR", {
    timeZone: "Asia/Seoul",
    weekday: "short",
    month: "numeric",
    day: "numeric",
  }).format(new Date(value));
}
function formatUpcoming(item: Upcoming) {
  return `${formatClassDate(item.classDate)} ${item.startTime.slice(0, 5)}`;
}
function assignmentLabel(status: string) {
  return status === "reviewed"
    ? "첨삭 완료"
    : status === "submitted"
      ? "첨삭 대기"
      : "제출 전";
}
function formatScore(value: number) {
  return Number.isInteger(value) ? String(value) : value.toFixed(1);
}
