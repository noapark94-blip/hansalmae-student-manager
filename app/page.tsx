"use client";

import type { FormEvent } from "react";
import { useEffect, useMemo, useState } from "react";
import type { User } from "@supabase/supabase-js";
import { createSupabaseBrowserClient, type Profile, type UserRole } from "./supabase";

type View = "dashboard" | "students" | "schedule" | "attendance" | "assignments" | "consultations";

const nav: { id: View; label: string; icon: string }[] = [
  { id: "dashboard", label: "홈", icon: "⌂" },
  { id: "students", label: "학생", icon: "人" },
  { id: "schedule", label: "시간표", icon: "▦" },
  { id: "attendance", label: "출결·보강", icon: "✓" },
  { id: "assignments", label: "과제·첨삭", icon: "✎" },
  { id: "consultations", label: "상담", icon: "☏" },
];

const roleLabels: Record<UserRole, string> = {
  admin: "관리자",
  teacher: "교사",
  student: "학생",
  guardian: "학부모",
};

const roleViews: Record<UserRole, View[]> = {
  admin: ["dashboard", "students", "schedule", "attendance", "assignments", "consultations"],
  teacher: ["dashboard", "students", "schedule", "attendance", "assignments", "consultations"],
  student: ["dashboard", "schedule", "attendance", "assignments"],
  guardian: ["dashboard", "schedule", "attendance", "consultations"],
};

const classes = [
  { time: "16:00", name: "중3 국어", teacher: "박선생", room: "A 강의실", present: 7, total: 8, tone: "berry" },
  { time: "17:30", name: "중2 수학 A", teacher: "김선생", room: "B 강의실", present: 9, total: 9, tone: "violet" },
  { time: "19:00", name: "고1 영어 B", teacher: "이선생", room: "A 강의실", present: 6, total: 8, tone: "navy" },
  { time: "20:30", name: "고2 수학 B", teacher: "김선생", room: "B 강의실", present: 5, total: 7, tone: "green" },
];

const students = [
  { name: "김민준", school: "배곧중 2", subjects: ["수학", "영어"], status: "재원", attendance: "96%" },
  { name: "이서연", school: "배곧고 1", subjects: ["국어", "영어", "수학"], status: "재원", attendance: "100%" },
  { name: "박지호", school: "서해중 3", subjects: ["국어"], status: "재원", attendance: "91%" },
  { name: "최하은", school: "군서고 2", subjects: ["영어", "수학"], status: "상담필요", attendance: "87%" },
  { name: "정유진", school: "배곧중 1", subjects: ["수학"], status: "재원", attendance: "98%" },
];

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

      const { data, error } = await supabase
        .from("profiles")
        .select("id, role, display_name")
        .eq("id", nextUser.id)
        .single<Profile>();

      if (error) setAuthError("계정 역할을 확인할 수 없습니다. 관리자에게 문의해 주세요.");
      setProfile(data ?? null);
      setAuthReady(true);
    };

    void supabase.auth.getUser().then(({ data }) => loadProfile(data.user));
    const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => {
      void loadProfile(session?.user ?? null);
    });
    return () => listener.subscription.unsubscribe();
  }, [supabase]);

  const allowedNav = profile ? nav.filter((item) => roleViews[profile.role].includes(item.id)) : [];

  const filteredStudents = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return students;
    return students.filter((student) =>
      [student.name, student.school, ...student.subjects].some((value) => value.toLowerCase().includes(q)),
    );
  }, [query]);

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
          {(profile.role === "admin" || profile.role === "teacher") && <button onClick={() => showToast("공지·문자 기능은 다음 단계에서 활성화돼요.")}><span className="nav-icon">✉</span>공지·문자</button>}
          {profile.role === "admin" && <button onClick={() => showToast("계정·역할 설정은 관리자만 사용할 수 있어요.")}><span className="nav-icon">⚙</span>설정</button>}
          <div className="teacher-card"><div className="avatar">{profile.display_name.slice(0, 1)}</div><div><b>{profile.display_name}</b><span>{roleLabels[profile.role]}</span></div><button className="signout-button" onClick={() => void supabase.auth.signOut()}>로그아웃</button></div>
        </div>
      </aside>

      {mobileNav && <button className="backdrop" aria-label="메뉴 닫기" onClick={() => setMobileNav(false)} />}

      <section className="workspace">
        <header className="topbar">
          <button className="menu-button" aria-label="메뉴 열기" onClick={() => setMobileNav(true)}>☰</button>
          <div className="search-wrap"><span>⌕</span><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="학생, 클래스 검색" /></div>
          <button className="icon-button" aria-label="알림" onClick={() => showToast("새로운 알림이 없어요.")}>♢<i /></button>
          <button className="primary small" onClick={() => showToast("학생 등록 화면은 Supabase 연결 후 활성화돼요.")}>＋ 학생 등록</button>
        </header>

        <div className="content">
          {view === "dashboard" && <Dashboard profile={profile} onNavigate={selectView} onToast={showToast} />}
          {view === "students" && <Students rows={filteredStudents} query={query} setQuery={setQuery} onToast={showToast} />}
          {view === "schedule" && <Schedule />}
          {view === "attendance" && <SimplePanel title="출결·보강" description="오늘 수업별 출결을 확인하고 결석 학생의 보강 일정을 관리합니다." items={["중3 국어 · 결석 1명", "고1 영어 B · 지각 1명 / 결석 1명", "이번 주 보강 예정 · 5건"]} />}
          {view === "assignments" && <SimplePanel title="과제·첨삭" description="클래스별 과제를 만들고 학생별 제출과 첨삭 상태를 확인합니다." items={["중2 수학 A · 미제출 4명", "고1 영어 B · 첨삭 대기 5건", "중3 국어 · 오늘 마감 3명"]} />}
          {view === "consultations" && <SimplePanel title="상담 관리" description="내부 상담 메모와 학부모 공유 피드백을 안전하게 분리합니다." items={["상담 권장 학생 · 7명", "이번 주 상담 예정 · 3건", "학부모 공유 대기 · 2건"]} />}
        </div>
      </section>
      {toast && <div className="toast" role="status">{toast}</div>}
    </main>
  );
}

function Dashboard({ profile, onNavigate, onToast }: { profile: Profile; onNavigate: (view: View) => void; onToast: (message: string) => void }) {
  if (profile.role === "student" || profile.role === "guardian") {
    return <FamilyDashboard profile={profile} onNavigate={onNavigate} />;
  }
  return <>
    <div className="page-heading"><div><p className="eyebrow">역할 · {roleLabels[profile.role]}</p><h1>안녕하세요, {profile.display_name}님</h1><p>{profile.role === "student" ? "내 수업과 학습 현황을 확인하세요." : profile.role === "guardian" ? "자녀의 수업과 출결 현황을 확인하세요." : "오늘 학원 운영 현황을 한눈에 확인하세요."}</p></div>{(profile.role === "admin" || profile.role === "teacher") && <button className="primary" onClick={() => onToast("새 공지 작성은 다음 단계에서 활성화돼요.")}>✦ 새 공지 작성</button>}</div>
    <section className="stats-grid">
      <Stat label="전체 재원생" value="96" unit="명" detail="이번 달 +4명" icon="人" tone="wine" />
      <Stat label="오늘 수업" value="8" unit="개" detail="다음 수업 16:00" icon="▦" tone="blue" />
      <Stat label="오늘 출석률" value="92" unit="%" detail="출석 37 · 결석 3" icon="✓" tone="green" />
      <Stat label="확인할 항목" value="24" unit="건" detail="과제 12 · 상담 7 · 보강 5" icon="!" tone="amber" />
    </section>
    <div className="dashboard-grid">
      <section className="panel today-panel"><PanelHeader title="오늘 수업" action="전체 시간표" onClick={() => onNavigate("schedule")} /><div className="class-list">{classes.map((item) => <div className="class-row" key={item.time}><time>{item.time}</time><span className={`class-bar ${item.tone}`} /><div className="class-info"><b>{item.name}</b><span>{item.teacher} · {item.room}</span></div><div className="attendance-pill"><span>출석</span><b>{item.present}/{item.total}</b></div><button aria-label={`${item.name} 상세`}>›</button></div>)}</div></section>
      <section className="panel attention-panel"><PanelHeader title="지금 확인해 주세요" /><div className="notice-list">{notices.map((notice) => <button key={notice.label} onClick={() => onNavigate(notice.label === "상담" ? "consultations" : notice.label === "과제" ? "assignments" : "attendance")}><span className={`notice-icon ${notice.tone}`}>{notice.label === "상담" ? "☏" : notice.label === "과제" ? "✎" : "↻"}</span><span><b>{notice.text}</b><small>{notice.label} 관리에서 확인하기</small></span><strong>{notice.count}</strong><i>›</i></button>)}</div></section>
      <section className="panel weekly-panel"><PanelHeader title="이번 주 출결" action="출결 관리" onClick={() => onNavigate("attendance")} /><div className="week-bars">{[["월",94],["화",91],["수",96],["목",89],["금",92]].map(([day,value]) => <div key={day}><span><b>{day}</b><small>{value}%</small></span><i><em style={{width:`${value}%`}} /></i></div>)}</div><div className="legend"><span><i className="dot wine" /> 출석 184</span><span><i className="dot amber" /> 지각 8</span><span><i className="dot gray" /> 결석 12</span></div></section>
      <section className="panel activity-panel"><PanelHeader title="최근 활동" /><div className="activity-list"><Activity icon="✓" tone="green" title="중2 수학 A 출결 완료" meta="학생 9명 · 12분 전"/><Activity icon="✎" tone="wine" title="영어 첨삭 피드백 5건 등록" meta="이선생 · 36분 전"/><Activity icon="☏" tone="blue" title="학부모 상담 기록 작성" meta="학생 1명 · 1시간 전"/><Activity icon="✉" tone="amber" title="수업 변경 안내 발송" meta="수신 8명 · 2시간 전"/></div></section>
    </div>
  </>;
}

function FamilyDashboard({ profile, onNavigate }: { profile: Profile; onNavigate: (view: View) => void }) {
  const isStudent = profile.role === "student";
  return <><div className="page-heading"><div><p className="eyebrow">역할 · {roleLabels[profile.role]}</p><h1>안녕하세요, {profile.display_name}님</h1><p>{isStudent ? "내 수업과 학습 현황을 확인하세요." : "자녀의 수업과 출결 현황을 확인하세요."}</p></div></div><section className="stats-grid family-stats"><Stat label="이번 주 수업" value="4" unit="개" detail="다음 수업 오늘 19:00" icon="▦" tone="blue" /><Stat label="이번 달 출석률" value="96" unit="%" detail="출석 12 · 결석 1" icon="✓" tone="green" /><Stat label={isStudent ? "제출할 과제" : "상담 기록"} value={isStudent ? "2" : "1"} unit="건" detail={isStudent ? "가장 가까운 마감 내일" : "최근 공유 8월 7일"} icon={isStudent ? "✎" : "☏"} tone="amber" /></section><div className="dashboard-grid"><section className="panel today-panel"><PanelHeader title="다가오는 수업" action="전체 시간표" onClick={() => onNavigate("schedule")} /><div className="class-list">{classes.slice(1, 3).map((item) => <div className="class-row" key={item.time}><time>{item.time}</time><span className={`class-bar ${item.tone}`} /><div className="class-info"><b>{item.name}</b><span>{item.teacher} · {item.room}</span></div></div>)}</div></section><section className="panel attention-panel"><PanelHeader title="최근 학습 현황" /><div className="notice-list"><button onClick={() => onNavigate("attendance")}><span className="notice-icon green">✓</span><span><b>이번 달 출석 12회</b><small>출결 내역 확인하기</small></span><i>›</i></button><button onClick={() => onNavigate(isStudent ? "assignments" : "consultations")}><span className="notice-icon amber">{isStudent ? "✎" : "☏"}</span><span><b>{isStudent ? "확인할 과제 2건" : "최근 상담 기록"}</b><small>{isStudent ? "과제 현황 확인하기" : "공유된 상담 내용 확인하기"}</small></span><i>›</i></button></div></section></div></>;
}

function Students({ rows, query, setQuery, onToast }: { rows: typeof students; query: string; setQuery: (value: string) => void; onToast: (message: string) => void }) {
  return <><div className="page-heading compact"><div><p className="eyebrow">학생 통합 관리</p><h1>학생</h1><p>학생은 한 번만 등록하고 여러 과목과 클래스를 연결합니다.</p></div><button className="primary" onClick={() => onToast("학생 등록 폼은 다음 단계에서 연결할게요.")}>＋ 학생 등록</button></div><section className="panel table-panel"><div className="table-tools"><div className="search-wrap inner"><span>⌕</span><input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="이름, 학교, 과목 검색" /></div><span>전체 {rows.length}명</span></div><div className="student-table"><div className="table-head"><span>학생</span><span>학교·학년</span><span>수강 과목</span><span>출석률</span><span>상태</span></div>{rows.map((student) => <button className="table-row" key={student.name} onClick={() => onToast(`${student.name} 학생 상세 화면은 다음 단계에서 연결할게요.`)}><span className="student-name"><i>{student.name.slice(0,1)}</i><b>{student.name}</b></span><span>{student.school}</span><span className="subject-tags">{student.subjects.map(subject => <em key={subject}>{subject}</em>)}</span><strong>{student.attendance}</strong><span><i className={`status ${student.status === "재원" ? "active" : "warning"}`}>{student.status}</i></span></button>)}</div></section></>;
}

function Schedule() {
  const hours = ["16:00", "17:30", "19:00", "20:30"];
  const days = ["월", "화", "수", "목", "금", "토"];
  return <><div className="page-heading compact"><div><p className="eyebrow">주간 운영</p><h1>시간표</h1><p>반복 수업과 날짜별 변경·휴강·보강을 함께 관리합니다.</p></div><button className="primary">＋ 수업 일정</button></div><section className="panel schedule-panel"><div className="schedule-toolbar"><button>‹</button><b>8월 10일 – 8월 15일</b><button>›</button><span>주간 보기⌄</span></div><div className="schedule-grid"><div className="corner" />{days.map(day => <div className="day" key={day}>{day}</div>)}{hours.flatMap((hour, row) => [<div className="hour" key={`${hour}-time`}>{hour}</div>, ...days.map((day, col) => { const matches = (row + col) % 3 === 0; const item = classes[(row + col) % classes.length]; return <div className="slot" key={`${day}-${hour}`}>{matches && <article className={item.tone}><b>{item.name}</b><span>{hour} · {item.teacher}</span><small>{item.room}</small></article>}</div>; })])}</div></section></>;
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
