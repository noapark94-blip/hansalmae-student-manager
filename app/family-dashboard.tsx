"use client";

import type { CSSProperties } from "react";
import { useCallback, useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Profile } from "./supabase";
import { FamilyLearningNote, type TodayLesson } from "./family-learning-note";
import { FamilyLearningReportFeed } from "./family-learning-report-feed";
import { FamilyExamGrowth } from "./family-exam-growth";
import { FamilyCorrectionExamGrowth } from "./family-correction-exam-growth";
import { HansalmaeIcon } from "./hansalmae-icons";
import { familyTeacherName, familyTeacherNames } from "./family-teacher-name";

type FamilyView =
  | "dashboard"
  | "schedule"
  | "attendance"
  | "makeups"
  | "assignments"
  | "reports"
  | "calendar"
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
type RegularCorrection = {
  id: string;
  subject: string;
  weekday: number;
  startTime: string;
  endTime: string;
  teacherName: string;
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
type SummaryLessonReport = {
  lessonId: string;
  lessonDate: string;
  startsAt: string;
  className: string;
  subject: string;
  mainSubject?: string;
  lessonContent: string;
  homeworkContent: string;
  attendance: { status: string; lateMinutes: number | null } | null;
  homeworkResult: { status: string; note: string } | null;
  exams: { score: number | null; maxScore: number; percent: number | null }[];
};
type SummaryCorrectionReport = {
  id: string;
  correctionDate: string;
  startTime: string;
  subject: string;
  attendanceStatus: string;
  examScore: number | null;
  examMaxScore: number | null;
  homeworkStatus: string | null;
  correctionContent: string;
  assistantFeedback: string;
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
function seoulDate() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Seoul", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
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
  const [todayLessons,setTodayLessons]=useState<TodayLesson[]>([]);
  const load = useCallback(
    async (id: string | null, background = false) => {
      if (!background) setLoading(true);
      if (!background) setError("");
      const [{ data: next, error: e },todayResult] = await Promise.all([
        supabase.rpc("family_live_dashboard", { p_student_id: id }),
        supabase.rpc("family_today_lessons", { p_student_id: id }),
      ]);
      if (e) setError("학습 현황을 불러오지 못했습니다.");
      else {
        const parsed = next as Data;
        setData((current) => JSON.stringify(current) === JSON.stringify(parsed) ? current : parsed);
        setSelectedId(parsed.selectedStudent?.id ?? null);
        if(!todayResult.error){const nextLessons=(todayResult.data??[]) as TodayLesson[];setTodayLessons((current)=>JSON.stringify(current)===JSON.stringify(nextLessons)?current:nextLessons)}
      }
      if (!background) setLoading(false);
    },
    [supabase],
  );
  useEffect(() => {
    void load(null);
  }, [load]);
  useEffect(()=>{
    const refresh=()=>{if(document.visibilityState==="visible")void load(selectedId,true)};
    const timer=window.setInterval(refresh,5000);
    window.addEventListener("focus",refresh);
    document.addEventListener("visibilitychange",refresh);
    return()=>{window.clearInterval(timer);window.removeEventListener("focus",refresh);document.removeEventListener("visibilitychange",refresh)};
  },[load,selectedId]);
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
  const effectiveTodayLessons = useMemo(() => {
    const scheduled = (data?.upcomingClasses ?? [])
      .filter((item) => item.classDate === seoulDate())
      .filter((item) => !todayLessons.some((lesson) => lesson.kind === "regular" && lesson.subject === item.subject && lesson.startTime.slice(0, 5) === item.startTime.slice(0, 5)))
      .map((item): TodayLesson => {
        const weekly = data?.weekClasses.find((row) => row.id === item.id);
        return {
          id: `scheduled:${item.id}`,
          kind: "regular",
          label: "정규수업",
          subject: item.subject || item.name,
          startTime: item.startTime,
          endTime: weekly?.endTime ?? item.startTime,
          teacherName: item.teachers,
          room: item.room ?? "",
          attendanceStatus: null,
        };
      });
    return [...todayLessons, ...scheduled].sort((a, b) => a.startTime.localeCompare(b.startTime));
  }, [data, todayLessons]);
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
      {profile.role === "student" && <section className="family-app-welcome">
        <p>
          {profile.role === "student"
            ? "오늘도 차근차근"
            : "자녀의 오늘을 확인하세요"}
        </p>
        <h1>
          {profile.role === "student"
            ? `안녕하세요, ${profile.display_name}님`
            : `${studentGivenName(selected?.name) ?? "자녀"}의 학습 공간`}
        </h1>
        <span>수업·출결·시험·숙제를 한곳에서 확인하세요.</span>
      </section>}
      {error && <p className="attendance-error">{error}</p>}
      {!selected ? (
        <section className="panel family-empty">
          <b>연결된 학생 정보가 없습니다.</b>
        </section>
      ) : (
        <>
          {profile.role === "student" && <section className="family-profile-card">
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
              <small>나의 학습 정보</small>
            </div>
            <i aria-hidden="true">›</i>
          </section>}
          {profile.role === "guardian" && (data?.children.length ?? 0) > 1 && (
            <label className="family-child-switcher">
              <span>자녀 선택</span>
              <select
                disabled={loading}
                value={selectedId ?? ""}
                onChange={(e) => void load(e.target.value)}
              >
                {data?.children.map((child) => (
                  <option key={child.id} value={child.id}>
                    {child.name} · {[child.school, child.grade].filter(Boolean).join(" ")}
                  </option>
                ))}
              </select>
            </label>
          )}
          <FamilyLearningNote
            studentName={selected.name}
            attendance={data?.recentAttendance ?? []}
            assignments={data?.assignments ?? []}
            announcements={data?.announcements ?? []}
            todayLessons={effectiveTodayLessons}
            nextLesson={data?.upcomingClasses[0] ?? null}
            onSchedule={() => onNavigate("schedule")}
            onNavigate={(view) =>
              onNavigate(view === "communications" ? "communications" : "reports")
            }
          />
          <FamilyLearningReportFeed
            supabase={supabase}
            studentId={selected.id}
            studentName={studentGivenName(selected.name) ?? selected.name}
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
              label="진행 중 과제"
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
                      : "진행 중인 과제 없음"
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
  const [corrections, setCorrections] = useState<RegularCorrection[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [scheduleFilter, setScheduleFilter] = useState("all");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const load = useCallback(async (studentId: string | null) => {
    setLoading(true);
    setError("");
    const [dashboardResult, correctionResult] = await Promise.all([
      supabase.rpc("family_live_dashboard", { p_student_id: studentId }),
      supabase.rpc("family_regular_correction_timetable", { p_student_id: studentId }),
    ]);
    const next = dashboardResult.data;
    if (dashboardResult.error || correctionResult.error || !next) setError("정규시간표를 불러오지 못했습니다.");
    else {
      const parsed = next as Data;
      setData(parsed);
      setCorrections((correctionResult.data ?? []) as RegularCorrection[]);
      setSelectedId(parsed.selectedStudent?.id ?? null);
    }
    setLoading(false);
  }, [supabase]);
  useEffect(() => { void load(null); }, [load]);
  if (loading && !data) return <section className="panel hub-message">정규시간표를 불러오는 중이에요…</section>;
  if (error && !data) return <section className="panel hub-message error">{error}</section>;
  const selected = data?.selectedStudent;
  const scheduleSubjects = Array.from(new Set((data?.weekClasses ?? []).map((item) => item.subject).filter(Boolean)));
  return <div className="family-schedule-page">
    <header className="family-schedule-heading">
      <p>{profile.role === "guardian" ? "자녀 정규 일정" : "나의 정규 일정"}</p>
      <h1>정규시간표</h1>
      <span>매주 반복되는 정규수업과 첨삭 시간을 한눈에 확인하세요.</span>
    </header>
    {error && <p className="attendance-error">{error}</p>}
    {selected ? <>
      <section className="family-schedule-student">
        <i>{selected.name.slice(0, 1)}</i>
        <span><b>{selected.name}</b><small>{[selected.school, selected.grade].filter(Boolean).join(" · ") || "한살매 학생"}</small></span>
        {profile.role === "guardian" && (data?.children.length ?? 0) > 1 && <select aria-label="자녀 선택" disabled={loading} value={selectedId ?? ""} onChange={(event) => void load(event.target.value)}>{data?.children.map((child) => <option key={child.id} value={child.id}>{child.name}</option>)}</select>}
      </section>
      <nav className="family-schedule-legend" aria-label="시간표 카테고리">
        <button type="button" className={scheduleFilter === "all" ? "active" : ""} onClick={() => setScheduleFilter("all")}>전체</button>
        {scheduleSubjects.map((subject) => <button type="button" key={subject} className={scheduleFilter === `subject:${subject}` ? "active" : ""} onClick={() => setScheduleFilter(`subject:${subject}`)}>{subject}</button>)}
        <button type="button" className={`correction ${scheduleFilter === "correction" ? "active" : ""}`} onClick={() => setScheduleFilter("correction")}>첨삭</button>
      </nav>
      <section className="family-weekly-schedule" aria-label={`${selected.name} 정규시간표`}>
        {weekdays.map((day, index) => {
          const classes = data?.weekClasses.filter((item) => item.weekday === index + 1) ?? [];
          const correctionClasses = corrections.filter((item) => item.weekday === index + 1);
          const schedules = [...classes.map((item) => ({ kind: "regular" as const, item })), ...correctionClasses.map((item) => ({ kind: "correction" as const, item }))]
            .filter((schedule) => scheduleFilter === "all" || (scheduleFilter === "correction" ? schedule.kind === "correction" : schedule.kind === "regular" && schedule.item.subject === scheduleFilter.slice(8)))
            .sort((a, b) => a.item.startTime.localeCompare(b.item.startTime));
          return <article key={day} className={schedules.length ? "has-class" : ""}>
            <header><b>{day}</b><span>{schedules.length ? `${schedules.length}개 수업` : "수업 없음"}</span></header>
            <div>{schedules.length ? schedules.map((schedule) => schedule.kind === "regular" ? <section className="regular" key={`regular-${schedule.item.id}`} style={{ "--family-class-color": schedule.item.color } as CSSProperties}>
              <time>{schedule.item.startTime.slice(0, 5)}–{schedule.item.endTime.slice(0, 5)}</time>
              <span><b>{schedule.item.name}</b><small>{schedule.item.subject} · {familyTeacherNames(schedule.item.teachers)}{schedule.item.room ? ` · ${schedule.item.room}` : ""}</small></span>
            </section> : <section className="correction" key={`correction-${schedule.item.id}`}>
              <time>{schedule.item.startTime.slice(0, 5)}–{schedule.item.endTime.slice(0, 5)}</time>
              <span><b>{schedule.item.subject} 첨삭수업</b></span>
            </section>) : <p>등록된 정규 일정이 없습니다.</p>}</div>
          </article>;
        })}
      </section>
    </> : <section className="panel family-empty"><b>연결된 학생 정보가 없습니다.</b></section>}
  </div>;
}

export function FamilyCalendarView({ supabase, profile }: { supabase: SupabaseClient; profile: Profile }) {
  const [data, setData] = useState<Data | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const load = useCallback(async (studentId: string | null) => {
    setLoading(true);
    setError("");
    const { data: next, error: loadError } = await supabase.rpc("family_live_dashboard", { p_student_id: studentId });
    if (loadError || !next) setError("학습캘린더를 불러오지 못했습니다.");
    else {
      const parsed = next as Data;
      setData(parsed);
      setSelectedId(parsed.selectedStudent?.id ?? null);
    }
    setLoading(false);
  }, [supabase]);
  useEffect(() => { void load(null); }, [load]);
  if (loading && !data) return <section className="panel hub-message">학습캘린더를 불러오는 중이에요…</section>;
  if (error && !data) return <section className="panel hub-message error">{error}</section>;
  const selected = data?.selectedStudent;
  return <div className="family-schedule-page family-calendar-page">
    <header className="family-schedule-heading">
      <p>{profile.role === "guardian" ? "자녀 학습 기록" : "나의 학습 기록"}</p>
      <h1>학습캘린더</h1>
      <span>예정 수업부터 출석·학습 기록까지 날짜별로 한눈에 확인하세요.</span>
    </header>
    {error && <p className="attendance-error">{error}</p>}
    {selected ? <>
      {profile.role === "guardian" && (data?.children.length ?? 0) > 1 && <label className="family-calendar-child-select"><span>자녀 선택</span><select disabled={loading} value={selectedId ?? ""} onChange={(event) => void load(event.target.value)}>{data?.children.map((child) => <option key={child.id} value={child.id}>{child.name}</option>)}</select></label>}
      <FamilyLearningReportFeed supabase={supabase} studentId={selected.id} studentName={selected.name} displayMode="calendar" />
    </> : <section className="panel family-empty"><b>연결된 학생 정보가 없습니다.</b></section>}
  </div>;
}

type SummaryRange = "daily" | "weekly" | "monthly";
const summaryRangeLabels: Record<SummaryRange, string> = { daily: "일간", weekly: "주간", monthly: "월간" };

function dateInSummaryRange(date: string, range: SummaryRange, today: string) {
  if (range === "daily") return date === today;
  if (range === "monthly") return date.slice(0, 7) === today.slice(0, 7);
  const target = new Date(`${date}T00:00:00+09:00`).getTime();
  const end = new Date(`${today}T23:59:59+09:00`).getTime();
  return target >= end - 6 * 86400000 && target <= end;
}

function summaryPeriodText(range: SummaryRange, today: string) {
  const [, month, day] = today.split("-").map(Number);
  if (range === "daily") return `${month}월 ${day}일 오늘`;
  if (range === "monthly") return `${month}월 한 달`;
  const start = new Date(new Date(`${today}T12:00:00+09:00`).getTime() - 6 * 86400000);
  const startParts = new Intl.DateTimeFormat("ko-KR", { timeZone: "Asia/Seoul", month: "numeric", day: "numeric" }).format(start);
  return `${startParts}–${month}. ${day}. 최근 7일`;
}

export function FamilySummaryReportView({ supabase, profile }: { supabase: SupabaseClient; profile: Profile }) {
  const [dashboard, setDashboard] = useState<Data | null>(null);
  const [lessons, setLessons] = useState<SummaryLessonReport[]>([]);
  const [corrections, setCorrections] = useState<SummaryCorrectionReport[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [range, setRange] = useState<SummaryRange>("weekly");
  const [visibleHighlightCount, setVisibleHighlightCount] = useState(3);
  const [detailTarget, setDetailTarget] = useState<{ lessonId?: string; correctionId?: string } | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const load = useCallback(async (studentId: string | null) => {
    setLoading(true);
    setError("");
    const dashboardResult = await supabase.rpc("family_live_dashboard", { p_student_id: studentId });
    if (dashboardResult.error || !dashboardResult.data) {
      setError("학습리포트를 불러오지 못했습니다.");
      setLoading(false);
      return;
    }
    const nextDashboard = dashboardResult.data as Data;
    const nextId = nextDashboard.selectedStudent?.id ?? null;
    setDashboard(nextDashboard);
    setSelectedId(nextId);
    if (!nextId) {
      setLessons([]);
      setCorrections([]);
      setLoading(false);
      return;
    }
    const [lessonResult, correctionResult] = await Promise.all([
      supabase.rpc("family_completed_learning_reports", { p_student_id: nextId, p_limit: 30 }),
      supabase.rpc("family_correction_reports", { p_student_id: nextId, p_limit: 50 }),
    ]);
    if (lessonResult.error || correctionResult.error) setError("일부 학습 기록을 불러오지 못했습니다.");
    setLessons((lessonResult.data ?? []) as SummaryLessonReport[]);
    setCorrections((correctionResult.data ?? []) as SummaryCorrectionReport[]);
    setLoading(false);
  }, [supabase]);
  useEffect(() => { void load(null); }, [load]);
  useEffect(() => { setVisibleHighlightCount(3); }, [range, selectedId]);

  const today = seoulDate();
  const periodLessons = lessons.filter((item) => dateInSummaryRange(item.lessonDate, range, today));
  const periodCorrections = corrections.filter((item) => dateInSummaryRange(item.correctionDate, range, today));
  const attendance = [
    ...periodLessons.map((item) => item.attendance?.status).filter(Boolean),
    ...periodCorrections.map((item) => item.attendanceStatus).filter(Boolean),
  ] as string[];
  const presentCount = attendance.filter((status) => status === "present").length;
  const lateCount = attendance.filter((status) => status === "late").length;
  const homeworkComplete = periodLessons.filter((item) => item.homeworkResult?.status === "complete").length
    + periodCorrections.filter((item) => item.homeworkStatus === "complete").length;
  const scoreValues = [
    ...periodLessons.flatMap((item) => item.exams.map((exam) => exam.percent ?? (exam.score !== null && exam.maxScore > 0 ? exam.score / exam.maxScore * 100 : null))),
    ...periodCorrections.map((item) => item.examScore !== null && (item.examMaxScore ?? 0) > 0 ? item.examScore / Number(item.examMaxScore) * 100 : null),
  ].filter((score): score is number => score !== null && Number.isFinite(score));
  const averageScore = scoreValues.length ? Math.round(scoreValues.reduce((sum, score) => sum + score, 0) / scoreValues.length) : null;
  const highlights = [
    ...periodLessons.map((item) => ({ id: `lesson-${item.lessonId}`, date: item.lessonDate, time: item.startsAt.slice(11, 16), type: item.subject || "정규수업", title: item.className, content: item.lessonContent || item.homeworkContent || "수업 기록이 저장됐어요.", tone: "regular" })),
    ...periodCorrections.map((item) => ({ id: `correction-${item.id}`, date: item.correctionDate, time: item.startTime.slice(0, 5), type: "첨삭", title: `${item.subject} 첨삭`, content: item.correctionContent || item.assistantFeedback || "첨삭 기록이 저장됐어요.", tone: "correction" })),
  ].sort((a, b) => `${b.date}${b.time}`.localeCompare(`${a.date}${a.time}`));
  const selected = dashboard?.selectedStudent;

  return <div className="family-summary-report-page">
    <header className="family-grades-heading">
      <p>{profile.role === "guardian" ? "자녀 학습 요약" : "나의 학습 요약"}</p>
      <h1>학습리포트</h1>
      <span>수업·첨삭·출결·과제·시험 기록을 기간별로 모아봤어요.</span>
    </header>
    {profile.role === "guardian" && (dashboard?.children.length ?? 0) > 1 && <label className="family-report-child-select">
      <span>자녀 선택</span>
      <select disabled={loading} value={selectedId ?? ""} onChange={(event) => void load(event.target.value)}>{dashboard?.children.map((child) => <option key={child.id} value={child.id}>{child.name}</option>)}</select>
    </label>}
    <nav className="family-report-range" aria-label="리포트 기간">
      {(Object.keys(summaryRangeLabels) as SummaryRange[]).map((item) => <button type="button" key={item} className={range === item ? "active" : ""} onClick={() => setRange(item)}>{summaryRangeLabels[item]}</button>)}
    </nav>
    {error && <p className="attendance-error">{error}</p>}
    {loading && !dashboard ? <section className="panel hub-message">학습리포트를 정리하고 있어요…</section> : !selected ? <section className="panel family-empty"><b>연결된 학생 정보가 없습니다.</b></section> : <>
      <section className="family-report-overview">
        <header><span><small>{summaryPeriodText(range, today)}</small><h2><em>{studentGivenName(selected.name)}</em>의 학습 요약</h2></span><i><HansalmaeIcon name="book" size={23} /></i></header>
        <div className="family-report-metrics">
          <article><small>학습 기록</small><b>{periodLessons.length + periodCorrections.length}<em>건</em></b><span>정규·보강·추가·첨삭</span></article>
          <article><small>출석</small><b>{presentCount}<em>회</em></b><span>{lateCount ? `지각 ${lateCount}회 포함` : "지각 없이 참여"}</span></article>
          <article><small>과제 완료</small><b>{homeworkComplete}<em>건</em></b><span>확인된 완료 기록</span></article>
          <article><small>평균 점수</small><b>{averageScore === null ? "–" : averageScore}<em>{averageScore === null ? "" : "점"}</em></b><span>{scoreValues.length ? `${scoreValues.length}개 시험 기준` : "기간 내 시험 없음"}</span></article>
        </div>
      </section>
      <section className="family-report-highlights">
        <header><span><p>핵심 학습 기록</p><h2>{summaryRangeLabels[range]} 기록</h2></span><small>{highlights.length}건</small></header>
        {highlights.length ? <div>{highlights.slice(0, visibleHighlightCount).map((item) => <article key={item.id} className={`${item.tone} clickable`} role="button" tabIndex={0} onClick={() => {
          setDetailTarget(item.tone === "correction" ? { correctionId: item.id.slice("correction-".length) } : { lessonId: item.id.slice("lesson-".length) });
        }} onKeyDown={(event) => {
          if (event.key !== "Enter" && event.key !== " ") return;
          event.preventDefault();
          event.currentTarget.click();
        }}>
          <time>{Number(item.date.slice(5, 7))}월 {Number(item.date.slice(8, 10))}일<small>{item.time}</small></time>
          <i />
          <span><small>{item.type}</small><b>{item.title}</b><p>{item.content}</p></span>
        </article>)}</div> : <div className="family-report-empty"><i><HansalmaeIcon name="book" size={24} /></i><b>이 기간에는 저장된 학습 기록이 없어요.</b><span>수업 기록이 저장되면 자동으로 리포트에 반영됩니다.</span></div>}
        {highlights.length > 3 && <button
          type="button"
          className={`family-report-history-toggle${visibleHighlightCount > 3 ? " open" : ""}`}
          aria-expanded={visibleHighlightCount > 3}
          onClick={() => setVisibleHighlightCount((current) => current >= highlights.length ? 3 : Math.min(highlights.length, current === 3 ? 10 : current + 10))}
        >
          <span>전체 기록 보기 <b>{highlights.length}</b></span>
          <i>{visibleHighlightCount === 3 ? "펼치기" : visibleHighlightCount < highlights.length ? "10개 더 보기" : "접기"}<em>⌄</em></i>
        </button>}
      </section>
    </>}
    {selectedId && detailTarget && <FamilyLearningReportFeed supabase={supabase} studentId={selectedId} detailTarget={detailTarget} detailOnly onDetailClose={() => setDetailTarget(null)} />}
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
function studentGivenName(name?: string | null) {
  const value = name?.trim();
  if (!value) return null;
  const compoundSurnames = ["남궁", "황보", "제갈", "선우", "서문", "독고", "동방", "사공"];
  const surnameLength = compoundSurnames.some((surname) => value.startsWith(surname)) ? 2 : 1;
  return value.length > surnameLength ? value.slice(surnameLength) : value;
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
