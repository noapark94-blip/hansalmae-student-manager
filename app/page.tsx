"use client";

import { useMemo, useState } from "react";

type View = "dashboard" | "students" | "schedule" | "attendance" | "assignments" | "consultations";

const nav: { id: View; label: string; icon: string }[] = [
  { id: "dashboard", label: "홈", icon: "⌂" },
  { id: "students", label: "학생", icon: "人" },
  { id: "schedule", label: "시간표", icon: "▦" },
  { id: "attendance", label: "출결·보강", icon: "✓" },
  { id: "assignments", label: "과제·첨삭", icon: "✎" },
  { id: "consultations", label: "상담", icon: "☏" },
];

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
  const [view, setView] = useState<View>("dashboard");
  const [query, setQuery] = useState("");
  const [mobileNav, setMobileNav] = useState(false);
  const [toast, setToast] = useState("");

  const filteredStudents = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return students;
    return students.filter((student) =>
      [student.name, student.school, ...student.subjects].some((value) => value.toLowerCase().includes(q)),
    );
  }, [query]);

  const selectView = (next: View) => {
    setView(next);
    setMobileNav(false);
    setQuery("");
  };

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
          {nav.map((item) => (
            <button key={item.id} className={view === item.id ? "active" : ""} onClick={() => selectView(item.id)}>
              <span className="nav-icon">{item.icon}</span>{item.label}
              {item.id === "assignments" && <em>12</em>}
            </button>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <button onClick={() => showToast("공지·문자 기능은 Supabase 연결 후 활성화돼요.")}><span className="nav-icon">✉</span>공지·문자</button>
          <button onClick={() => showToast("설정 화면은 다음 단계에서 연결할게요.")}><span className="nav-icon">⚙</span>설정</button>
          <div className="teacher-card"><div className="avatar">박</div><div><b>박노아 선생님</b><span>관리자</span></div><span>⋮</span></div>
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
          {view === "dashboard" && <Dashboard onNavigate={selectView} onToast={showToast} />}
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

function Dashboard({ onNavigate, onToast }: { onNavigate: (view: View) => void; onToast: (message: string) => void }) {
  return <>
    <div className="page-heading"><div><p className="eyebrow">2026년 8월 10일 월요일</p><h1>좋은 아침이에요, 박노아 선생님</h1><p>오늘 학원 운영 현황을 한눈에 확인하세요.</p></div><button className="primary" onClick={() => onToast("새 공지 작성은 Supabase 연결 후 활성화돼요.")}>✦ 새 공지 작성</button></div>
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

function Stat({ label, value, unit, detail, icon, tone }: { label: string; value: string; unit: string; detail: string; icon: string; tone: string }) { return <article className="stat-card"><div className={`stat-icon ${tone}`}>{icon}</div><div><span>{label}</span><p><strong>{value}</strong> {unit}</p><small>{detail}</small></div></article>; }
function PanelHeader({ title, action, onClick }: { title: string; action?: string; onClick?: () => void }) { return <div className="panel-header"><h2>{title}</h2>{action && <button onClick={onClick}>{action} <span>›</span></button>}</div>; }
function Activity({ icon, tone, title, meta }: { icon: string; tone: string; title: string; meta: string }) { return <div className="activity"><span className={`notice-icon ${tone}`}>{icon}</span><div><b>{title}</b><small>{meta}</small></div></div>; }
