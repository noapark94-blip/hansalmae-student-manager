"use client";

import type { FormEvent, ReactNode } from "react";
import { useEffect, useMemo, useState } from "react";
import type { User } from "@supabase/supabase-js";
import { createSupabaseBrowserClient, type AcademyClass, type Profile, type StudentRow, type UserRole } from "./supabase";
import { TeacherScheduleHub } from "./teacher-schedule-hub";
import { AttendanceBoard } from "./attendance-board";
import { MakeupBoard } from "./makeup-board";
import { AssignmentBoard } from "./assignment-board";
import { ConsultationBoard } from "./consultation-board";
import { CommunicationBoard } from "./communication-board";
import { SettingsBoard } from "./settings-board";
import { MyAccount } from "./my-account";
import { StudentDetailHub } from "./student-detail-hub";
import { FamilyLiveDashboard } from "./family-dashboard";
import { OperationsAuditBoard } from "./operations-audit";
import { StudentLifecycleDashboard, type StudentStatusFilter } from "./student-lifecycle-dashboard";
import { NotificationCenter } from "./notification-center";
import { TuitionBoard } from "./tuition-board";
import { TuitionRulesBoard } from "./tuition-rules-board";
import { OperationsAnalytics } from "./operations-analytics";

type View = "dashboard" | "students" | "schedule" | "corrections" | "transport" | "attendance" | "makeups" | "assignments" | "consultations" | "communications" | "tuition" | "tuition-settings" | "analytics" | "settings" | "my-account" | "audit";
type StudentFormValues = { name: string; school: string; grade: string; phone: string; status: string; internalNote: string };
type StudentDetails = StudentFormValues & { id: string };
type ClassFormValues = { name: string; subject: string; room: string; color: string };
type LiveTodayClass = { id: string; time: string; name: string; room: string | null; color: string; teachers: string; enrolled: number; present: number };
type LiveAttendance = { present: number; late: number; absent: number; checked: number };
type LiveDashboard = { todayClasses: LiveTodayClass[]; attendance: LiveAttendance & { makeup: number }; weekAttendance: (LiveAttendance & { weekday: number })[] };
type AssignmentCount = { unsubmitted: number; reviewPending: number; total: number };
type ConsultationCount = { overdue: number; upcoming: number };
type PauseReturnAlerts={overdue:number;upcoming:number;students:{id:string;name:string;expectedOn:string;overdue:boolean}[]};

const nav: { id: View; label: string; icon: string }[] = [
  { id: "dashboard", label: "홈", icon: "⌂" },
  { id: "students", label: "학생", icon: "人" },
  { id: "schedule", label: "전과목 시간표", icon: "▦" },
  { id: "corrections", label: "첨삭 시간표", icon: "✎" },
  { id: "transport", label: "차량 운행표", icon: "◇" },
  { id: "attendance", label: "출결 입력", icon: "✓" },
  { id: "makeups", label: "보강 일정", icon: "↻" },
  { id: "assignments", label: "과제·첨삭", icon: "✎" },
  { id: "consultations", label: "상담", icon: "☏" },
  { id: "communications", label: "공지·문자", icon: "✉" },
  { id: "tuition", label: "수납·미납", icon: "₩" },
  { id: "tuition-settings", label: "수강료 설정", icon: "￦" },
  { id: "analytics", label: "운영 통계", icon: "▥" },
];

const roleLabels: Record<UserRole, string> = {
  admin: "관리자",
  teacher: "교사",
  student: "학생",
  guardian: "학부모",
};

const roleViews: Record<UserRole, View[]> = {
  admin: ["dashboard", "students", "schedule", "corrections", "transport", "attendance", "makeups", "assignments", "consultations", "communications", "tuition", "tuition-settings", "analytics", "settings", "my-account", "audit"],
  teacher: ["dashboard", "students", "schedule", "corrections", "transport", "attendance", "makeups", "assignments", "consultations", "communications", "tuition", "tuition-settings", "my-account"],
  student: ["dashboard", "schedule", "attendance", "makeups", "assignments", "communications", "tuition", "my-account"],
  guardian: ["dashboard", "schedule", "attendance", "makeups", "consultations", "communications", "tuition", "my-account"],
};

const notices = [
  { label: "상담", text: "마지막 상담 후 30일이 지난 학생", count: 7, tone: "wine" },
  { label: "과제", text: "오늘까지 제출하지 않은 과제", count: 12, tone: "amber" },
  { label: "보강", text: "이번 주 예정된 보강 수업", count: 5, tone: "blue" },
];

export default function Home() {
  const supabase = useMemo(() => createSupabaseBrowserClient(), []);
  const [authReady, setAuthReady] = useState(!supabase);
  const [user, setUser] = useState<User | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [authError, setAuthError] = useState("");
  const [view, setView] = useState<View>("dashboard");
  const [query, setQuery] = useState("");
  const [mobileNav, setMobileNav] = useState(false);
  const [toast, setToast] = useState("");
  const [students, setStudents] = useState<StudentRow[]>([]);
  const [studentsLoading, setStudentsLoading] = useState(false);
  const [studentsError, setStudentsError] = useState("");
  const [registrationOpen, setRegistrationOpen] = useState(false);
  const [academyClasses, setAcademyClasses] = useState<AcademyClass[]>([]);
  const [classRegistrationOpen, setClassRegistrationOpen] = useState(false);
  const [enrollmentStudent, setEnrollmentStudent] = useState<StudentRow | null>(null);
  const [studentDetails, setStudentDetails] = useState<StudentDetails | null>(null);
  const [studentStatusFilter, setStudentStatusFilter] = useState<StudentStatusFilter>("all");

  useEffect(() => {
    if (!supabase) {
      return;
    }

    const loadProfile = async (nextUser: User | null) => {
      setUser(nextUser);
      if (!nextUser) {
        setProfile(null);
        setAuthReady(true);
        return;
      }

      const [{ data: role, error }, { data: ownProfile }] = await Promise.all([
        supabase.rpc("current_user_role"),
        supabase.from("profiles").select("display_name").eq("id", nextUser.id).maybeSingle(),
      ]);

      if (error || !role || !roleViews[role as UserRole]) {
        setAuthError("계정 역할을 확인할 수 없습니다. 관리자에게 문의해 주세요.");
        setProfile(null);
      } else {
        setAuthError("");
        setProfile({
          id: nextUser.id,
          role: role as UserRole,
          display_name:
            ownProfile?.display_name ??
            nextUser.user_metadata.display_name ??
            nextUser.user_metadata.full_name ??
            nextUser.email?.split("@")[0] ??
            "사용자",
        });
      }
      setAuthReady(true);
    };

    void supabase.auth.getUser().then(({ data }) => loadProfile(data.user));
    const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => {
      void loadProfile(session?.user ?? null);
    });
    return () => listener.subscription.unsubscribe();
  }, [supabase]);

  useEffect(() => {
    if (!supabase || !profile || (profile.role !== "admin" && profile.role !== "teacher")) {
      return;
    }

    let active = true;
    const loadStudents = async () => {
      setStudentsLoading(true);
      setStudentsError("");
      const [{ data, error }, { data: classData, error: classError }] = await Promise.all([
        supabase.rpc("staff_student_roster"),
        supabase.from("classes").select("id, name, subject, room, color, active").eq("active", true).order("name"),
      ]);

      if (!active) return;
      if (error || classError) {
        setStudentsError("학생 데이터를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.");
        setStudents([]);
      } else {
        setStudents(((data ?? []) as StudentRow[]).sort((a, b) => a.name.localeCompare(b.name, "ko")));
        setAcademyClasses((classData ?? []) as AcademyClass[]);
      }
      setStudentsLoading(false);
    };

    void loadStudents();
    return () => { active = false; };
  }, [profile, supabase]);

  const allowedNav = profile ? nav.filter((item) => roleViews[profile.role].includes(item.id)) : [];

  const filteredStudents = useMemo(() => {
    const q = query.trim().toLowerCase();
    return students.filter((student) => {
      const matchesStatus=studentStatusFilter==="all"||normalizeStudentStatus(student.status)===studentStatusFilter;
      const matchesQuery=!q||[student.name, student.school ?? "", student.grade ?? "", ...getStudentSubjects(student)].some((value) => value.toLowerCase().includes(q));
      return matchesStatus&&matchesQuery;
    });
  }, [query, studentStatusFilter, students]);

  const selectView = (next: View) => {
    if (profile && !roleViews[profile.role].includes(next)) {
      showToast("이 역할에서는 접근할 수 없는 메뉴예요.");
      return;
    }
    setView(next);
    setMobileNav(false);
    setQuery("");
  };

  if (!authReady) return <LoadingScreen />;
  if (!supabase) return <ConfigurationScreen />;
  if (!user) return <LoginScreen onSubmit={async (email, password) => {
    setAuthError("");
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    if (error) setAuthError("이메일 또는 비밀번호를 확인해 주세요.");
  }} error={authError} />;
  if (!profile) return <AccessPendingScreen email={user.email ?? ""} error={authError} onSignOut={() => void supabase.auth.signOut()} />;

  const showToast = (message: string) => {
    setToast(message);
    window.setTimeout(() => setToast(""), 2200);
  };

  const registerStudent = async (values: StudentFormValues) => {
    const { data, error } = await supabase
      .from("students")
      .insert({
        name: values.name.trim(),
        school: values.school.trim() || null,
        grade: values.grade.trim() || null,
        phone: values.phone.trim() || null,
        status: values.status,
        internal_note: values.internalNote.trim() || null,
      })
      .select("id, name, school, grade, status")
      .single();

    if (error) throw error;
    const created = { ...data, enrollments: [] } as StudentRow;
    setStudents((current) => [...current, created].sort((a, b) => a.name.localeCompare(b.name, "ko")));
    setStudentsError("");
    setRegistrationOpen(false);
    setView("students");
    showToast(`${created.name} 학생을 등록했습니다.`);
  };

  const registerClass = async (values: ClassFormValues) => {
    const { data, error } = await supabase.from("classes").insert({ name: values.name.trim(), subject: values.subject.trim(), room: values.room.trim() || null, color: values.color }).select("id, name, subject, room, color, active").single();
    if (error) throw error;
    setAcademyClasses((current) => [...current, data as AcademyClass].sort((a, b) => a.name.localeCompare(b.name, "ko")));
    setClassRegistrationOpen(false);
    showToast(`${data.name} 클래스를 등록했습니다.`);
  };

  const assignClass = async (student: StudentRow, classId: string) => {
    const selectedClass = academyClasses.find((item) => item.id === classId);
    if (!selectedClass) throw new Error("class not found");
    const { error } = await supabase.from("enrollments").insert({ student_id: student.id, class_id: classId, status: "active" });
    if (error) throw error;
    setStudents((current) => current.map((item) => item.id === student.id ? { ...item, enrollments: [...item.enrollments, { class_id: classId, status: "active", classes: { name: selectedClass.name, subject: selectedClass.subject } }] } : item));
    setEnrollmentStudent(null);
    showToast(`${student.name} 학생에게 ${selectedClass.name} 클래스를 배정했습니다.`);
  };

  const openStudentDetails = async (student: StudentRow) => {
    const { data, error } = await supabase.from("students").select("id, name, school, grade, phone, status, internal_note").eq("id", student.id).single();
    if (error) { showToast("학생 상세 정보를 불러오지 못했습니다."); return; }
    setStudentDetails({ id: data.id, name: data.name, school: data.school ?? "", grade: data.grade ?? "", phone: data.phone ?? "", status: data.status, internalNote: data.internal_note ?? "" });
  };

  const updateStudent = async (values: StudentDetails) => {
    const { data, error } = await supabase.from("students").update({ name: values.name.trim(), school: values.school.trim() || null, grade: values.grade.trim() || null, phone: values.phone.trim() || null, status: values.status, internal_note: values.internalNote.trim() || null }).eq("id", values.id).select("id, name, school, grade, status").single();
    if (error) throw error;
    setStudents((current) => current.map((student) => student.id === values.id ? { ...student, ...data } : student).sort((a, b) => a.name.localeCompare(b.name, "ko")));
    setStudentDetails(null);
    showToast(`${data.name} 학생 정보를 수정했습니다.`);
  };

  const deleteStudent = async (student: StudentDetails) => {
    const { error } = await supabase.from("students").delete().eq("id", student.id);
    if (error) throw error;
    setStudents((current) => current.filter((item) => item.id !== student.id));
    setStudentDetails(null);
    showToast(`${student.name} 학생을 삭제했습니다.`);
  };

  return (
    <main className="app-shell">
      <aside className={`sidebar ${mobileNav ? "is-open" : ""}`}>
        <div className="brand">
          <img className="brand-mark" src="/hansalmae-logo.png" alt="한살매 로고" />
          <div><strong>한살매</strong><span>학생관리</span></div>
        </div>
        <nav aria-label="주요 메뉴">
          {allowedNav.map((item) => (
            <button key={item.id} className={view === item.id ? "active" : ""} onClick={() => selectView(item.id)}>
              <span className="nav-icon">{item.icon}</span>{item.label}
              {item.id === "assignments" && <em>12</em>}
            </button>
          ))}
        </nav>
        <div className="sidebar-bottom">
          {profile.role === "admin" && <button className={view === "audit" ? "active" : ""} onClick={() => selectView("audit")}><span className="nav-icon">◉</span>운영 점검</button>}
          {profile.role === "admin" && <button className={view === "settings" ? "active" : ""} onClick={() => selectView("settings")}><span className="nav-icon">⚙</span>계정·역할</button>}
          <button className={view === "my-account" ? "active" : ""} onClick={() => selectView("my-account")}><span className="nav-icon">♙</span>내 계정</button>
          <div className="teacher-card"><div className="avatar">{profile.display_name.slice(0, 1)}</div><div><b>{profile.display_name}</b><span>{roleLabels[profile.role]}</span></div><button className="signout-button" onClick={() => void supabase.auth.signOut()}>로그아웃</button></div>
        </div>
      </aside>

      {mobileNav && <button className="backdrop" aria-label="메뉴 닫기" onClick={() => setMobileNav(false)} />}

      <section className="workspace">
        <header className="topbar">
          <button className="menu-button" aria-label="메뉴 열기" onClick={() => setMobileNav(true)}>☰</button>
          <div className="search-wrap"><span>⌕</span><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="학생, 클래스 검색" /></div>
          <NotificationCenter supabase={supabase} />
          {(profile.role === "admin" || profile.role === "teacher") && <button className="primary small" onClick={() => setRegistrationOpen(true)}>＋ 학생 등록</button>}
        </header>

        <div className="content">
          {view === "dashboard" && <Dashboard supabase={supabase} profile={profile} activeStudentCount={students.filter(isActiveStudent).length} studentsLoading={studentsLoading} onNavigate={selectView} />}
          {view === "students" && <><StudentLifecycleDashboard supabase={supabase} filter={studentStatusFilter} onFilter={setStudentStatusFilter}/><Students rows={filteredStudents} total={students.length} filteredTotal={filteredStudents.length} statusFilter={studentStatusFilter} loading={studentsLoading} error={studentsError} query={query} setQuery={setQuery} onRegister={() => setRegistrationOpen(true)} onOpen={openStudentDetails} /></>}
          {view === "schedule" && (profile.role === "admin" || profile.role === "teacher" ? <TeacherScheduleHub supabase={supabase} profile={profile} initialTab="all" /> : <Schedule classes={academyClasses} onRegister={() => setClassRegistrationOpen(true)} />)}
          {view === "corrections" && <TeacherScheduleHub supabase={supabase} profile={profile} initialTab="correction" />}
          {view === "transport" && <TeacherScheduleHub supabase={supabase} profile={profile} initialTab="vehicle" />}
          {view === "attendance" && (profile.role === "admin" || profile.role === "teacher" ? <AttendanceBoard supabase={supabase} /> : <SimplePanel title="출결·보강" description="내 수업의 출결 기록을 확인합니다." items={["출결 기록은 담당 선생님이 입력합니다."]} />)}
          {view === "makeups" && <MakeupBoard supabase={supabase} />}
          {view === "assignments" && <AssignmentBoard supabase={supabase} />}
          {view === "consultations" && <ConsultationBoard supabase={supabase} />}
          {view === "communications" && <CommunicationBoard supabase={supabase} />}
          {view === "tuition" && <TuitionBoard supabase={supabase} />}
          {view === "tuition-settings" && <TuitionRulesBoard supabase={supabase} />}
          {view === "analytics" && <OperationsAnalytics supabase={supabase} />}
          {view === "settings" && <SettingsBoard supabase={supabase} />}
          {view === "audit" && <OperationsAuditBoard supabase={supabase} onNavigate={selectView} />}
          {view === "my-account" && <MyAccount supabase={supabase} profile={profile} email={user.email ?? ""} onProfileUpdated={(displayName) => setProfile((current) => current ? { ...current, display_name:displayName } : current)} />}
        </div>
      </section>
      {registrationOpen && <StudentRegistrationModal onClose={() => setRegistrationOpen(false)} onSubmit={registerStudent} />}
      {classRegistrationOpen && <ClassRegistrationModal onClose={() => setClassRegistrationOpen(false)} onSubmit={registerClass} />}
      {enrollmentStudent && <EnrollmentModal student={enrollmentStudent} classes={academyClasses} onClose={() => setEnrollmentStudent(null)} onSubmit={(classId) => assignClass(enrollmentStudent, classId)} />}
      {studentDetails && <StudentDetailHub supabase={supabase} student={studentDetails} rosterStudent={students.find((item) => item.id === studentDetails.id)} onClose={() => setStudentDetails(null)} onUpdate={updateStudent} onDelete={deleteStudent} onAssign={(student) => { setStudentDetails(null); setEnrollmentStudent(student as StudentRow); }} onLifecycleUpdated={(status) => { setStudentDetails((current) => current ? { ...current, status } : current); setStudents((current) => current.map((item) => item.id === studentDetails.id ? { ...item, status, enrollments:status === "active" ? item.enrollments : item.enrollments.map((enrollment) => enrollment.status === "active" ? { ...enrollment, status:status === "paused" ? "paused" : "completed" } : enrollment) } : item)); }} />}
      {toast && <div className="toast" role="status">{toast}</div>}
    </main>
  );
}

function Dashboard({ supabase, profile, activeStudentCount, studentsLoading, onNavigate }: { supabase: NonNullable<ReturnType<typeof createSupabaseBrowserClient>>; profile: Profile; activeStudentCount: number; studentsLoading: boolean; onNavigate: (view: View) => void }) {
  const [live, setLive] = useState<LiveDashboard | null>(null);
  const [assignmentCount, setAssignmentCount] = useState<AssignmentCount | null>(null);
  const [consultationCount, setConsultationCount] = useState<ConsultationCount | null>(null);
  const [pauseReturns,setPauseReturns]=useState<PauseReturnAlerts|null>(null);
  const [liveError, setLiveError] = useState(false);
  useEffect(() => {
    if (profile.role === "student" || profile.role === "guardian") return;
    let active = true;
    void Promise.all([supabase.rpc("staff_dashboard_live"), supabase.rpc("assignment_dashboard_count"), supabase.rpc("consultation_dashboard_count"),supabase.rpc("staff_pause_return_alerts",{p_days:7})]).then(([dashboard, assignments, consultations,pauseAlerts]) => {
      if (!active) return;
      if (dashboard.error || !dashboard.data) setLiveError(true);
      else setLive(dashboard.data as LiveDashboard);
      if (!assignments.error && assignments.data) setAssignmentCount(assignments.data as AssignmentCount);
      if (!consultations.error && consultations.data) setConsultationCount(consultations.data as ConsultationCount);
      if (!pauseAlerts.error&&pauseAlerts.data)setPauseReturns(pauseAlerts.data as PauseReturnAlerts);
    });
    return () => { active = false; };
  }, [profile.role, supabase]);
  if (profile.role === "student" || profile.role === "guardian") {
    return <FamilyLiveDashboard supabase={supabase} profile={profile} onNavigate={onNavigate} />;
  }
  const attendance = live?.attendance;
  const attendanceRate = attendance?.checked ? Math.round((attendance.present / attendance.checked) * 100) : null;
  const nextClass = live?.todayClasses.find((item) => item.time.slice(0,5) >= new Date().toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", hour12: false, timeZone: "Asia/Seoul" }));
  const weekTotals = (live?.weekAttendance ?? []).reduce((total, day) => ({ present: total.present + day.present, late: total.late + day.late, absent: total.absent + day.absent }), { present: 0, late: 0, absent: 0 });
  return <>
    <div className="page-heading"><div><p className="eyebrow">역할 · {roleLabels[profile.role]}</p><h1>안녕하세요, {profile.display_name}님</h1><p>{profile.role === "student" ? "내 수업과 학습 현황을 확인하세요." : profile.role === "guardian" ? "자녀의 수업과 출결 현황을 확인하세요." : "오늘 학원 운영 현황을 한눈에 확인하세요."}</p></div>{(profile.role === "admin" || profile.role === "teacher") && <button className="primary" onClick={() => onNavigate("communications")}>✦ 새 공지 작성</button>}</div>
    <section className="stats-grid">
      <Stat label="전체 재원생" value={studentsLoading ? "…" : String(activeStudentCount)} unit="명" detail="Supabase 실시간 기준" icon="人" tone="wine" />
      <Stat label="오늘 수업" value={live ? String(live.todayClasses.length) : "…"} unit="개" detail={nextClass ? `다음 수업 ${nextClass.time.slice(0,5)}` : live ? "오늘 남은 수업 없음" : "Supabase 확인 중"} icon="▦" tone="blue" />
      <Stat label="오늘 출석률" value={attendanceRate === null ? "–" : String(attendanceRate)} unit={attendanceRate === null ? "" : "%"} detail={attendance?.checked ? `출석 ${attendance.present} · 지각 ${attendance.late} · 결석 ${attendance.absent}` : "아직 기록된 출결 없음"} icon="✓" tone="green" />
      <Stat label="확인할 항목" value={attendance ? String(attendance.makeup) : "…"} unit="건" detail="보강 필요 출결 기준" icon="!" tone="amber" />
    </section>
    <section className="teacher-schedule-shortcuts" aria-label="선생님 시간표 바로가기"><button onClick={() => onNavigate("schedule")}><span>▦</span><b>학원 전과목 시간표</b><small>공동담당·개인 시간표 연동</small></button><button onClick={() => onNavigate("corrections")}><span>✎</span><b>첨삭 시간표</b><small>월–금 90분 고정 슬롯</small></button><button onClick={() => onNavigate("transport")}><span>◇</span><b>차량 운행 시간표</b><small>차량실장님·탑승 위치·학생</small></button></section>
    {pauseReturns&&(pauseReturns.overdue+pauseReturns.upcoming)>0&&<button className={`pause-return-banner${pauseReturns.overdue?" overdue":""}`} onClick={()=>onNavigate("students")}><span>↗</span><div><b>{pauseReturns.overdue?`복귀 예정일이 지난 휴원생 ${pauseReturns.overdue}명`:`7일 이내 복귀 예정 휴원생 ${pauseReturns.upcoming}명`}</b><small>{pauseReturns.students.slice(0,4).map((item)=>`${item.name} ${formatShortDate(item.expectedOn)}`).join(" · ")}</small></div><i>학생 현황에서 확인 ›</i></button>}
    <div className="dashboard-grid">
      <section className="panel today-panel"><PanelHeader title="오늘 수업" action="전체 시간표" onClick={() => onNavigate("schedule")} /><div className="class-list">{live?.todayClasses.map((item) => <div className="class-row" key={item.id}><time>{item.time.slice(0,5)}</time><span className="class-bar" style={{ background:item.color }} /><div className="class-info"><b>{item.name}</b><span>{item.teachers}{item.room ? ` · ${item.room}` : ""}</span></div><div className="attendance-pill"><span>출석</span><b>{item.present}/{item.enrolled}</b></div><button aria-label={`${item.name} 상세`} onClick={() => onNavigate("attendance")}>›</button></div>)}{live && live.todayClasses.length === 0 && <p className="dashboard-empty">오늘 등록된 수업이 없습니다.</p>}{!live && <p className={`dashboard-empty${liveError ? " error" : ""}`}>{liveError ? "오늘 일정을 불러오지 못했습니다." : "오늘 일정을 불러오는 중이에요…"}</p>}</div></section>
      <section className="panel attention-panel"><PanelHeader title="지금 확인해 주세요" /><div className="notice-list">{notices.map((notice) => { const text = notice.label === "과제" && assignmentCount ? `미제출 ${assignmentCount.unsubmitted}건 · 첨삭 대기 ${assignmentCount.reviewPending}건` : notice.label === "상담" && consultationCount ? `30일 이상 미상담 ${consultationCount.overdue}명 · 예정 ${consultationCount.upcoming}건` : notice.label === "보강" && attendance ? `보강이 필요한 결석 기록 ${attendance.makeup}건` : notice.text; const count = notice.label === "과제" && assignmentCount ? assignmentCount.total : notice.label === "상담" && consultationCount ? consultationCount.overdue : notice.label === "보강" && attendance ? attendance.makeup : notice.count; return <button key={notice.label} onClick={() => onNavigate(notice.label === "상담" ? "consultations" : notice.label === "과제" ? "assignments" : "makeups")}><span className={`notice-icon ${notice.tone}`}>{notice.label === "상담" ? "☏" : notice.label === "과제" ? "✎" : "↻"}</span><span><b>{text}</b><small>{notice.label} 관리에서 확인하기</small></span><strong>{count}</strong><i>›</i></button>; })}</div></section>
      <section className="panel weekly-panel"><PanelHeader title="이번 주 출결" action="출결 관리" onClick={() => onNavigate("attendance")} /><div className="week-bars">{(live?.weekAttendance ?? []).map((day) => { const value = day.checked ? Math.round((day.present / day.checked) * 100) : 0; return <div key={day.weekday}><span><b>{["월","화","수","목","금"][day.weekday - 1]}</b><small>{day.checked ? `${value}%` : "–"}</small></span><i><em style={{width:`${value}%`}} /></i></div>; })}</div><div className="legend"><span><i className="dot wine" /> 출석 {weekTotals.present}</span><span><i className="dot amber" /> 지각 {weekTotals.late}</span><span><i className="dot gray" /> 결석 {weekTotals.absent}</span></div></section>
      <section className="panel activity-panel"><PanelHeader title="오늘 운영 집계" /><div className="activity-list"><Activity icon="✓" tone="green" title={`출결 입력 ${attendance?.checked ?? 0}건`} meta={`출석 ${attendance?.present ?? 0} · 지각 ${attendance?.late ?? 0} · 결석 ${attendance?.absent ?? 0}`}/><Activity icon="✎" tone="wine" title={`확인할 과제 ${assignmentCount?.total ?? 0}건`} meta={`미제출 ${assignmentCount?.unsubmitted ?? 0} · 첨삭 대기 ${assignmentCount?.reviewPending ?? 0}`}/><Activity icon="☏" tone="blue" title={`상담 점검 학생 ${consultationCount?.overdue ?? 0}명`} meta={`예정 상담 ${consultationCount?.upcoming ?? 0}건`}/><Activity icon="↻" tone="amber" title={`보강 필요 ${attendance?.makeup ?? 0}건`} meta="실시간 출결 기록 기준"/></div></section>
    </div>
  </>;
}

function Students({ rows, total, filteredTotal, statusFilter, loading, error, query, setQuery, onRegister, onOpen }: { rows: StudentRow[]; total: number; filteredTotal:number; statusFilter:StudentStatusFilter; loading: boolean; error: string; query: string; setQuery: (value: string) => void; onRegister: () => void; onOpen: (student: StudentRow) => void }) {
  return <><div className="page-heading compact"><div><p className="eyebrow">학생 통합 관리</p><h1>학생</h1><p>학생을 선택하면 상세 정보와 수강 클래스를 관리할 수 있습니다.</p></div><button className="primary" onClick={onRegister}>＋ 학생 등록</button></div><section className="panel table-panel"><div className="table-tools"><div className="search-wrap inner"><span>⌕</span><input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="이름, 학교, 과목 검색" /></div><span>{statusFilter==="all"?`전체 ${total}명`:`검색 결과 ${filteredTotal}명`}</span></div><div className="student-table"><div className="table-head"><span>학생</span><span>학교·학년</span><span>수강 과목</span><span>출석률</span><span>상태</span></div>{loading ? <StudentTableMessage>학생 데이터를 불러오는 중이에요…</StudentTableMessage> : error ? <StudentTableMessage error>{error}</StudentTableMessage> : rows.length === 0 ? <StudentTableMessage>{query||statusFilter!=="all" ? "선택한 조건의 학생이 없습니다." : "아직 등록된 학생이 없습니다."}</StudentTableMessage> : rows.map((student) => { const subjects = getStudentSubjects(student); const normalizedStatus=normalizeStudentStatus(student.status); return <button className="table-row" key={student.id} onClick={() => onOpen(student)}><span className="student-name"><i>{student.name.slice(0,1)}</i><b>{student.name}</b></span><span>{[student.school, student.grade].filter(Boolean).join(" · ") || "-"}</span><span className="subject-tags">{subjects.length ? subjects.map(subject => <em key={subject}>{subject}</em>) : <em>미배정</em>}</span><strong>-</strong><span><i className={`status ${normalizedStatus==="active"?"active":normalizedStatus==="paused"?"warning":"completed"}`}>{studentStatusLabel(student.status)}</i></span></button>; })}</div></section></>;
}

function StudentRegistrationModal({ onClose, onSubmit }: { onClose: () => void; onSubmit: (values: StudentFormValues) => Promise<void> }) {
  const [values, setValues] = useState<StudentFormValues>({ name: "", school: "", grade: "", phone: "", status: "active", internalNote: "" });
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");
  const update = (field: keyof StudentFormValues, value: string) => setValues((current) => ({ ...current, [field]: value }));
  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setSubmitting(true);
    setError("");
    try {
      await onSubmit(values);
    } catch {
      setError("학생을 등록하지 못했습니다. 입력 내용을 확인하고 다시 시도해 주세요.");
      setSubmitting(false);
    }
  };
  return <div className="modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><section className="student-modal" role="dialog" aria-modal="true" aria-labelledby="student-registration-title"><header><div><p className="eyebrow">SUPABASE 학생 관리</p><h2 id="student-registration-title">학생 등록</h2><span>기본 정보를 먼저 등록하고 수강 과목은 이후 연결합니다.</span></div><button type="button" aria-label="닫기" onClick={onClose}>×</button></header><form onSubmit={submit}><div className="form-grid"><label>학생 이름 <b>*</b><input autoFocus required value={values.name} onChange={(event) => update("name", event.target.value)} placeholder="예: 김민준" /></label><label>학교<input value={values.school} onChange={(event) => update("school", event.target.value)} placeholder="예: 배곧중학교" /></label><label>학년<input value={values.grade} onChange={(event) => update("grade", event.target.value)} placeholder="예: 중2" /></label><label>학생 연락처<input type="tel" value={values.phone} onChange={(event) => update("phone", event.target.value)} placeholder="010-0000-0000" /></label><label>재원 상태<select value={values.status} onChange={(event) => update("status", event.target.value)}><option value="active">재원</option><option value="paused">휴원</option><option value="completed">퇴원</option></select></label><label className="full">내부 메모<textarea value={values.internalNote} onChange={(event) => update("internalNote", event.target.value)} placeholder="관리자와 교사만 확인할 메모" rows={3} /></label></div>{error && <p className="form-error" role="alert">{error}</p>}<footer><button type="button" className="secondary-button" onClick={onClose}>취소</button><button className="primary" disabled={submitting}>{submitting ? "저장 중…" : "학생 등록"}</button></footer></form></section></div>;
}

function ClassRegistrationModal({ onClose, onSubmit }: { onClose: () => void; onSubmit: (values: ClassFormValues) => Promise<void> }) {
  const [values, setValues] = useState<ClassFormValues>({ name: "", subject: "", room: "", color: "#922D61" });
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");
  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault(); setSubmitting(true); setError("");
    try { await onSubmit(values); } catch { setError("클래스를 등록하지 못했습니다. 다시 시도해 주세요."); setSubmitting(false); }
  };
  return <ModalShell eyebrow="SUPABASE 수업 관리" title="클래스 등록" description="클래스와 과목을 등록한 뒤 학생에게 배정합니다." onClose={onClose}><form onSubmit={submit}><div className="form-grid"><label>클래스 이름 <b>*</b><input autoFocus required value={values.name} onChange={(event) => setValues({ ...values, name: event.target.value })} placeholder="예: 고3 영어 A" /></label><label>과목 <b>*</b><input required value={values.subject} onChange={(event) => setValues({ ...values, subject: event.target.value })} placeholder="예: 영어" /></label><label>강의실<input value={values.room} onChange={(event) => setValues({ ...values, room: event.target.value })} placeholder="예: A 강의실" /></label><label>표시 색상<input type="color" value={values.color} onChange={(event) => setValues({ ...values, color: event.target.value })} /></label></div>{error && <p className="form-error">{error}</p>}<ModalActions onClose={onClose} submitting={submitting} submitLabel="클래스 등록" /></form></ModalShell>;
}

function EnrollmentModal({ student, classes, onClose, onSubmit }: { student: StudentRow; classes: AcademyClass[]; onClose: () => void; onSubmit: (classId: string) => Promise<void> }) {
  const assigned = new Set(student.enrollments.filter((item) => item.status === "active").map((item) => item.class_id));
  const available = classes.filter((item) => !assigned.has(item.id));
  const [classId, setClassId] = useState(available[0]?.id ?? "");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");
  const submit = async (event: FormEvent<HTMLFormElement>) => { event.preventDefault(); setSubmitting(true); setError(""); try { await onSubmit(classId); } catch { setError("수강 과목을 배정하지 못했습니다. 이미 배정된 클래스인지 확인해 주세요."); setSubmitting(false); } };
  return <ModalShell eyebrow="학생 수강 관리" title={`${student.name} · 클래스 배정`} description="등록된 클래스 중 수강할 클래스를 선택합니다." onClose={onClose}><form onSubmit={submit}>{available.length ? <div className="class-choice-list">{available.map((item) => <label key={item.id} className={classId === item.id ? "selected" : ""}><input type="radio" name="class" value={item.id} checked={classId === item.id} onChange={() => setClassId(item.id)} /><i style={{ background:item.color }} /><span><b>{item.name}</b><small>{item.subject}{item.room ? ` · ${item.room}` : ""}</small></span></label>)}</div> : <p className="modal-empty">배정 가능한 클래스가 없습니다. 시간표에서 클래스를 먼저 등록해 주세요.</p>}{error && <p className="form-error">{error}</p>}<ModalActions onClose={onClose} submitting={submitting} submitLabel="수강 배정" disabled={!classId} /></form></ModalShell>;
}

function ModalShell({ eyebrow, title, description, onClose, children }: { eyebrow: string; title: string; description: string; onClose: () => void; children: ReactNode }) {
  return <div className="modal-backdrop" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose(); }}><section className="student-modal" role="dialog" aria-modal="true"><header><div><p className="eyebrow">{eyebrow}</p><h2>{title}</h2><span>{description}</span></div><button type="button" aria-label="닫기" onClick={onClose}>×</button></header>{children}</section></div>;
}

function ModalActions({ onClose, submitting, submitLabel, disabled = false }: { onClose: () => void; submitting: boolean; submitLabel: string; disabled?: boolean }) {
  return <footer><button type="button" className="secondary-button" onClick={onClose}>취소</button><button className="primary" disabled={submitting || disabled}>{submitting ? "저장 중…" : submitLabel}</button></footer>;
}

function StudentTableMessage({ children, error = false }: { children: string; error?: boolean }) {
  return <div className={`student-table-message${error ? " error" : ""}`}>{children}</div>;
}

function getStudentSubjects(student: StudentRow) {
  return [...new Set(student.enrollments.filter((item) => item.status === "active").map((item) => item.classes?.subject).filter((subject): subject is string => Boolean(subject)))];
}

function isActiveStudent(student: StudentRow) {
  return student.status === "active" || student.status === "재원";
}

function normalizeStudentStatus(status:string):Exclude<StudentStatusFilter,"all"> {
  return status==="active"||status==="재원"?"active":status==="paused"||status==="휴원"?"paused":"completed";
}

function formatShortDate(value:string){return new Intl.DateTimeFormat("ko-KR",{timeZone:"Asia/Seoul",month:"short",day:"numeric"}).format(new Date(value))}

function studentStatusLabel(status: string) {
  return ({ active: "재원", paused: "휴원", completed: "퇴원" } as Record<string, string>)[status] ?? status;
}

function Schedule({ classes, onRegister }: { classes: AcademyClass[]; onRegister: () => void }) {
  return <><div className="page-heading compact"><div><p className="eyebrow">수업 운영</p><h1>클래스</h1><p>Supabase에 클래스를 등록하고 학생에게 수강 과목을 배정합니다.</p></div><button className="primary" onClick={onRegister}>＋ 클래스 등록</button></div><section className="panel class-panel"><div className="panel-header"><h2>운영 클래스</h2><span>전체 {classes.length}개</span></div>{classes.length ? <div className="academy-class-grid">{classes.map((item) => <article key={item.id}><i style={{ background:item.color }} /><div><b>{item.name}</b><span>{item.subject}{item.room ? ` · ${item.room}` : ""}</span></div><em>운영 중</em></article>)}</div> : <div className="modal-empty">아직 등록된 클래스가 없습니다. 위의 클래스 등록 버튼을 눌러 시작하세요.</div>}</section></>;
}

function SimplePanel({ title, description, items }: { title: string; description: string; items: string[] }) {
  return <><div className="page-heading compact"><div><p className="eyebrow">한살매 관리</p><h1>{title}</h1><p>{description}</p></div><button className="primary">＋ 새 기록</button></div><section className="panel simple-panel"><h2>오늘 확인할 항목</h2>{items.map((item, index) => <button key={item}><span>{index + 1}</span><b>{item}</b><i>›</i></button>)}</section></>;
}

function LoginScreen({ onSubmit, error }: { onSubmit: (email: string, password: string) => Promise<void>; error: string }) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setSubmitting(true);
    await onSubmit(email, password);
    setSubmitting(false);
  };
  return <main className="auth-shell"><section className="auth-card"><img src="/hansalmae-logo.png" alt="한살매 로고" /><p className="eyebrow">HANSALMAE ACADEMY</p><h1>한살매 학생관리</h1><p className="auth-copy">등록된 교사·학생·학부모 계정으로 로그인하세요.</p><form onSubmit={submit}><label>이메일<input type="email" value={email} onChange={(event) => setEmail(event.target.value)} autoComplete="email" required placeholder="name@example.com" /></label><label>비밀번호<input type="password" value={password} onChange={(event) => setPassword(event.target.value)} autoComplete="current-password" required placeholder="비밀번호" /></label>{error && <p className="auth-error" role="alert">{error}</p>}<button className="primary" disabled={submitting}>{submitting ? "로그인 중…" : "로그인"}</button></form><small>계정과 역할 변경은 학원 관리자에게 문의해 주세요.</small></section></main>;
}

function LoadingScreen() { return <main className="auth-shell"><section className="auth-card loading"><img src="/hansalmae-logo.png" alt="" /><p>로그인 정보를 확인하고 있어요…</p></section></main>; }
function ConfigurationScreen() { return <main className="auth-shell"><section className="auth-card"><img src="/hansalmae-logo.png" alt="한살매 로고" /><h1>연결 설정이 필요합니다</h1><p className="auth-copy">Supabase 공개 URL과 anon key를 환경 변수에 등록해 주세요.</p></section></main>; }
function AccessPendingScreen({ email, error, onSignOut }: { email: string; error: string; onSignOut: () => void }) { return <main className="auth-shell"><section className="auth-card"><img src="/hansalmae-logo.png" alt="한살매 로고" /><h1>접근 권한 확인</h1><p className="auth-copy">{error || `${email} 계정에 아직 역할이 지정되지 않았습니다.`}</p><button className="secondary-button" onClick={onSignOut}>다른 계정으로 로그인</button></section></main>; }

function Stat({ label, value, unit, detail, icon, tone }: { label: string; value: string; unit: string; detail: string; icon: string; tone: string }) { return <article className="stat-card"><div className={`stat-icon ${tone}`}>{icon}</div><div><span>{label}</span><p><strong>{value}</strong> {unit}</p><small>{detail}</small></div></article>; }
function PanelHeader({ title, action, onClick }: { title: string; action?: string; onClick?: () => void }) { return <div className="panel-header"><h2>{title}</h2>{action && <button onClick={onClick}>{action} <span>›</span></button>}</div>; }
function Activity({ icon, tone, title, meta }: { icon: string; tone: string; title: string; meta: string }) { return <div className="activity"><span className={`notice-icon ${tone}`}>{icon}</span><div><b>{title}</b><small>{meta}</small></div></div>; }
