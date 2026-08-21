"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { FormEvent } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Profile } from "./supabase";
import { isMilitaryTime, MilitaryTimeInput } from "./military-time-input";
import { SpecialLessonLearningBoard } from "./special-lesson-learning-board";

type Student = { id: string; name: string; school: string | null; grade: string | null };
type Session = {
  id: string;
  date: string;
  startTime: string;
  endTime: string;
  kind: "makeup" | "additional";
  room: string | null;
  note: string | null;
  teacherName: string;
  teacherId: string;
  students: Student[];
};
type Draft = Omit<Session, "id" | "students" | "teacherName" | "teacherId" | "room" | "note"> & { id: string; room: string; note: string; studentIds: string[] };
const blank = (): Draft => ({ id: "", date: today(), startTime: "", endTime: "", kind: "makeup", room: "", note: "", studentIds: [] });

export function TeacherSpecialLessons({ supabase, profile }: { supabase: SupabaseClient; profile: Profile }) {
  const [sessions, setSessions] = useState<Session[]>([]);
  const [students, setStudents] = useState<Student[]>([]);
  const [draft, setDraft] = useState<Draft | null>(null);
  const [activeSession, setActiveSession] = useState<Session | null>(null);
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [anchorDate, setAnchorDate] = useState(today());
  const [calendarOpen, setCalendarOpen] = useState(false);
  const [calendarMonth, setCalendarMonth] = useState(today().slice(0, 7));
  const load = useCallback(async () => {
    setLoading(true);
    const [{ data: sessionData, error: sessionError }, { data: studentData, error: studentError }] = await Promise.all([
      supabase.rpc("staff_teacher_special_lessons", { p_teacher_id: profile.role === "admin" ? null : profile.id }),
      supabase.rpc("staff_special_lesson_student_options", { p_teacher_id: profile.id }),
    ]);
    if (sessionError || studentError) setError(sessionError?.message ?? studentError?.message ?? "일정을 불러오지 못했습니다.");
    else {
      setSessions((sessionData ?? []) as Session[]);
      setStudents((studentData ?? []) as Student[]);
      setError("");
    }
    setLoading(false);
  }, [profile.id, supabase]);
  useEffect(() => void load(), [load]);
  useEffect(() => {
    const closeTopLayer = (event: KeyboardEvent) => {
      if (event.key !== "Escape") return;
      if (draft) setDraft(null);
      else if (activeSession) setActiveSession(null);
    };
    document.addEventListener("keydown", closeTopLayer);
    return () => document.removeEventListener("keydown", closeTopLayer);
  }, [activeSession, draft]);
  const visibleStudents = useMemo(() => {
    const keyword = query.trim().toLocaleLowerCase("ko");
    return keyword ? students.filter((item) => [item.name, item.school, item.grade].some((value) => value?.toLocaleLowerCase("ko").includes(keyword))) : students;
  }, [query, students]);
  const week = useMemo(() => weekDates(anchorDate), [anchorDate]);
  const sessionsByDate = useMemo(() => {
    const grouped = new Map<string, Session[]>();
    sessions.forEach((session) => grouped.set(session.date, [...(grouped.get(session.date) ?? []), session]));
    return grouped;
  }, [sessions]);
  const selectedDaySessions = sessionsByDate.get(anchorDate) ?? [];
  const edit = (session: Session) => setDraft({ id: session.id, date: session.date, startTime: session.startTime.slice(0, 5), endTime: session.endTime.slice(0, 5), kind: session.kind, room: session.room ?? "", note: session.note ?? "", studentIds: session.students.map((item) => item.id) });
  const save = async (event: FormEvent) => {
    event.preventDefault();
    if (!draft) return;
    if (!isMilitaryTime(draft.startTime) || !isMilitaryTime(draft.endTime) || draft.endTime <= draft.startTime) return setError("시작·종료 시간을 24시간제 4자리로 정확히 입력해 주세요.");
    if (!draft.studentIds.length) return setError("수업에 참여할 학생을 한 명 이상 선택해 주세요.");
    setSaving(true);
    const { error: saveError } = await supabase.rpc("staff_save_teacher_special_lesson", {
      p_id: draft.id || null,
      p_teacher_id: profile.id,
      p_date: draft.date,
      p_start_time: draft.startTime,
      p_end_time: draft.endTime,
      p_kind: draft.kind,
      p_room: draft.room.trim() || null,
      p_note: draft.note.trim() || null,
      p_student_ids: draft.studentIds,
    });
    if (saveError) setError(saveError.message);
    else {
      setDraft(null);
      setQuery("");
      await load();
    }
    setSaving(false);
  };
  const remove = async (session: Session) => {
    if (!confirm(`${session.date} ${session.startTime.slice(0, 5)} 일정을 삭제할까요?`)) return;
    const { error: removeError } = await supabase.rpc("staff_delete_teacher_special_lesson", { p_id: session.id });
    if (removeError) setError(removeError.message);
    else {
      if (activeSession?.id === session.id) setActiveSession(null);
      await load();
    }
  };
  return (
    <section className="panel teacher-special-workspace">
      <header>
        <div><p className="eyebrow">{profile.role === "admin" ? "관리자 전체 조회" : "선생님 전용"}</p><h2>개별 보강·추가수업</h2><span>정규 클래스와 분리하여 원하는 날짜와 시간에 학생을 배정합니다.</span></div>
        <button type="button" className="primary" onClick={() => { setError(""); setDraft({ ...blank(), date: anchorDate }); }}>＋ 일정 등록</button>
      </header>
      {error ? <p className="form-error special-lesson-error">{error}</p> : null}
      <section className="special-week-calendar">
        <header><div><h3>이번 주 수업 기록</h3><p>날짜를 선택해 보강·추가수업 일정을 확인하고 수업 기록을 관리합니다.</p></div><button type="button" className="secondary-button" onClick={() => { setCalendarMonth(anchorDate.slice(0, 7)); setCalendarOpen(true); }}>전체 캘린더</button></header>
        <div className="class-week-navigation special-week-navigation"><button type="button" aria-label="이전 주" onClick={() => setAnchorDate(shiftDate(anchorDate, -7))}>‹</button><div className="class-week-strip special-week-strip">{week.map((date, index) => {
          const daySessions = sessionsByDate.get(date) ?? [];
          const selectDay = () => { setAnchorDate(date); setActiveSession(null); };
          return <article key={date} role="button" tabIndex={0} className={`${date === anchorDate ? "active" : ""} ${daySessions.length ? "scheduled" : ""}`} onClick={selectDay} onKeyDown={(event) => { if (event.key === "Enter" || event.key === " ") selectDay(); }}>
            <div className="special-week-day"><span>{weekdays[index]}</span><b>{+date.slice(8)}</b><small>{daySessions.length ? `${daySessions.length}개 일정` : "일정 없음"}</small></div>
            {daySessions.map((session) => <button type="button" key={session.id} className={`special-week-session ${activeSession?.id === session.id ? "active" : ""}`} onClick={(event) => { event.stopPropagation(); setAnchorDate(date); setActiveSession(session); }}><b><time>{session.startTime.slice(0,5)}–{session.endTime.slice(0,5)}</time><em>{session.kind === "makeup" ? "보강" : "추가"}</em></b><span>{session.students.map((student) => student.name).join(" · ") || "학생 미배정"}</span></button>)}
          </article>;
        })}</div><button type="button" aria-label="다음 주" onClick={() => setAnchorDate(shiftDate(anchorDate, 7))}>›</button></div>
      </section>
      {loading ? <p className="settings-empty">일정을 불러오는 중이에요…</p> : (
        activeSession ? <SpecialLessonLearningBoard embedded supabase={supabase} sessionId={activeSession.id} onClose={() => setActiveSession(null)} onEdit={() => { setActiveSession(null); edit(activeSession); }} /> : <section className="special-day-agenda">
          <header><div><p className="eyebrow">선택한 날짜</p><h3>{formatDate(anchorDate)}</h3><span>{selectedDaySessions.length ? `${selectedDaySessions.length}개의 일정` : "등록된 일정이 없습니다."}</span></div></header>
          <div className="special-lesson-list">{selectedDaySessions.map((session) => <article key={session.id}>
            <i />
            <span><small>{session.kind === "makeup" ? "보강" : "추가수업"}</small><b>{formatDate(session.date)} · {session.startTime.slice(0, 5)}–{session.endTime.slice(0, 5)}</b><em>{session.students.map((item) => item.name).join(" · ") || "학생 미배정"}{session.room ? ` · ${session.room}` : ""}</em>{session.note ? <p>{session.note}</p> : null}</span>
            {profile.role === "admin" ? <mark>{session.teacherName}</mark> : null}
            <div><button type="button" className="primary compact" onClick={() => setActiveSession(session)}>수업 관리</button>{session.teacherId === profile.id ? <button type="button" className="secondary-button" onClick={() => edit(session)}>수정</button> : null}<button type="button" className="danger-button" onClick={() => void remove(session)}>삭제</button></div>
          </article>)}{!selectedDaySessions.length ? <p className="settings-empty">이 날짜에는 일정이 없습니다. 위 버튼으로 새 일정을 등록해 주세요.</p> : null}</div>
        </section>
      )}
      {calendarOpen ? <div className="modal-backdrop nested" onMouseDown={(event) => { if (event.target === event.currentTarget) setCalendarOpen(false); }}><section className="student-modal class-month-modal correction-month-modal" role="dialog" aria-modal="true" aria-label="보강·추가수업 전체 캘린더"><header><div><p className="eyebrow">전체 일정</p><h2>전체 캘린더</h2><span>월간 보강·추가수업 일정을 한눈에 확인합니다.</span></div><button type="button" aria-label="닫기" onClick={() => setCalendarOpen(false)}>×</button></header><nav className="correction-month-toolbar" aria-label="월 이동"><button type="button" aria-label="이전 달" onClick={() => setCalendarMonth(shiftMonth(calendarMonth, -1))}>‹</button><strong>{formatMonth(calendarMonth)}</strong><button type="button" aria-label="다음 달" onClick={() => setCalendarMonth(shiftMonth(calendarMonth, 1))}>›</button><button type="button" onClick={() => setCalendarMonth(today().slice(0, 7))}>이번 달</button></nav><div className="correction-month-weekdays">{weekdays.map((day) => <b key={day}>{day}</b>)}</div><div className="correction-month-grid">{monthDates(calendarMonth).map((date) => { const daySessions = sessionsByDate.get(date) ?? []; const inMonth = date.slice(0, 7) === calendarMonth; return <button type="button" key={date} className={`${inMonth ? "" : "outside"} ${date === anchorDate ? "selected" : ""} ${date === today() ? "today" : ""} ${daySessions.length ? "scheduled" : ""}`} onClick={() => { setAnchorDate(date); setActiveSession(null); setCalendarOpen(false); }}><span>{+date.slice(8)}</span><div>{daySessions.slice(0, 3).map((session) => <em key={session.id}>{session.startTime.slice(0, 5)} · {session.kind === "makeup" ? "보강" : "추가"}</em>)}{daySessions.length > 3 ? <small>+{daySessions.length - 3}개</small> : null}{!daySessions.length ? <small className="empty">일정 없음</small> : null}</div></button>; })}</div></section></div> : null}
      {draft ? <div className="modal-backdrop nested"><section role="dialog" aria-modal="true" aria-label={draft.id ? "보강 일정 수정" : "보강 일정 등록"} className="student-modal special-lesson-modal"><header><div><p className="eyebrow">개별 보강·추가수업</p><h2>{draft.id ? "일정 수정" : "새 일정"}</h2><span>날짜와 시간, 학생을 순서대로 선택해 주세요.</span></div><button type="button" aria-label="닫기" onClick={() => setDraft(null)}>×</button></header>
        <form onSubmit={(event) => void save(event)}>
          <div className="form-pair"><label>수업 구분<select value={draft.kind} onChange={(event) => setDraft({ ...draft, kind: event.target.value as Draft["kind"] })}><option value="makeup">보강</option><option value="additional">추가수업</option></select></label><label>날짜<input type="date" required value={draft.date} onChange={(event) => setDraft({ ...draft, date: event.target.value })} /></label></div>
          <div className="form-pair special-time-fields"><MilitaryTimeInput label="시작 시간" value={draft.startTime} onChange={(value) => setDraft({ ...draft, startTime: value })} /><MilitaryTimeInput label="종료 시간" value={draft.endTime} onChange={(value) => setDraft({ ...draft, endTime: value })} /></div>
          <div className="form-pair"><label>강의실<input value={draft.room ?? ""} onChange={(event) => setDraft({ ...draft, room: event.target.value })} placeholder="선택 입력" /></label><label>메모<input value={draft.note ?? ""} onChange={(event) => setDraft({ ...draft, note: event.target.value })} placeholder="수업 내용·준비물" /></label></div>
          <label className="special-student-search">학생 선택<input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="이름·학교·학년 검색" /></label>
          <div className="special-student-options">{visibleStudents.map((student) => { const active = draft.studentIds.includes(student.id); return <button type="button" className={active ? "active" : ""} key={student.id} onClick={() => setDraft({ ...draft, studentIds: active ? draft.studentIds.filter((id) => id !== student.id) : [...draft.studentIds, student.id] })}><i>{student.name[0]}</i><span><b>{student.name}</b><small>{[student.school, student.grade].filter(Boolean).join(" · ")}</small></span><em>{active ? "선택됨" : "선택"}</em></button>; })}{!visibleStudents.length ? <p className="settings-empty">담당 클래스의 재원생이 없습니다.</p> : null}</div>
          {error ? <p className="form-error">{error}</p> : null}<footer><button type="button" className="secondary-button" onClick={() => setDraft(null)}>취소</button><button className="primary" disabled={saving}>{saving ? "저장 중…" : "일정 저장"}</button></footer>
        </form>
      </section></div> : null}
    </section>
  );
}

function today() { return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Seoul", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date()); }
function formatDate(value: string) { return new Intl.DateTimeFormat("ko-KR", { timeZone: "Asia/Seoul", month: "long", day: "numeric", weekday: "short" }).format(new Date(`${value}T00:00:00+09:00`)); }
const weekdays = ["월", "화", "수", "목", "금", "토", "일"];
function shiftDate(value: string, days: number) { const date = new Date(`${value}T00:00:00+09:00`); date.setDate(date.getDate() + days); return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Seoul", year: "numeric", month: "2-digit", day: "2-digit" }).format(date); }
function weekDates(value: string) { const date = new Date(`${value}T00:00:00+09:00`); const mondayOffset = (date.getDay() + 6) % 7; date.setDate(date.getDate() - mondayOffset); return Array.from({ length: 7 }, (_, index) => { const current = new Date(date); current.setDate(date.getDate() + index); return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Seoul", year: "numeric", month: "2-digit", day: "2-digit" }).format(current); }); }
function shiftMonth(value: string, amount: number) { const [year, month] = value.split("-").map(Number); const next = new Date(Date.UTC(year, month - 1 + amount, 1)); return `${next.getUTCFullYear()}-${String(next.getUTCMonth() + 1).padStart(2, "0")}`; }
function formatMonth(value: string) { const [year, month] = value.split("-").map(Number); return `${year}년 ${month}월`; }
function monthDates(value: string) { const [year, month] = value.split("-").map(Number); const first = new Date(Date.UTC(year, month - 1, 1)); const mondayOffset = (first.getUTCDay() + 6) % 7; first.setUTCDate(first.getUTCDate() - mondayOffset); return Array.from({ length: 42 }, (_, index) => { const current = new Date(first); current.setUTCDate(first.getUTCDate() + index); return current.toISOString().slice(0, 10); }); }
