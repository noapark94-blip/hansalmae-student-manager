"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import type { FormEvent } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Profile } from "./supabase";
import { isMilitaryTime, MilitaryTimeInput } from "./military-time-input";

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
  const [query, setQuery] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
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
  const visibleStudents = useMemo(() => {
    const keyword = query.trim().toLocaleLowerCase("ko");
    return keyword ? students.filter((item) => [item.name, item.school, item.grade].some((value) => value?.toLocaleLowerCase("ko").includes(keyword))) : students;
  }, [query, students]);
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
    else await load();
  };
  return (
    <section className="panel teacher-special-workspace">
      <header>
        <div><p className="eyebrow">{profile.role === "admin" ? "관리자 전체 조회" : "선생님 전용"}</p><h2>개별 보강·추가수업</h2><span>정규 클래스와 분리하여 원하는 날짜와 시간에 학생을 배정합니다.</span></div>
        <button className="primary" onClick={() => { setError(""); setDraft(blank()); }}>＋ 일정 등록</button>
      </header>
      {error ? <p className="form-error special-lesson-error">{error}</p> : null}
      {loading ? <p className="settings-empty">일정을 불러오는 중이에요…</p> : (
        <div className="special-lesson-list">
          {sessions.map((session) => <article key={session.id}>
            <i />
            <span><small>{session.kind === "makeup" ? "보강" : "추가수업"}</small><b>{formatDate(session.date)} · {session.startTime.slice(0, 5)}–{session.endTime.slice(0, 5)}</b><em>{session.students.map((item) => item.name).join(" · ") || "학생 미배정"}{session.room ? ` · ${session.room}` : ""}</em>{session.note ? <p>{session.note}</p> : null}</span>
            {profile.role === "admin" ? <mark>{session.teacherName}</mark> : null}
            <div>{session.teacherId === profile.id ? <button className="secondary-button" onClick={() => edit(session)}>수정</button> : null}<button className="danger-button" onClick={() => void remove(session)}>삭제</button></div>
          </article>)}
          {!sessions.length ? <p className="settings-empty">등록된 보강·추가수업 일정이 없습니다.</p> : null}
        </div>
      )}
      {draft ? <div className="modal-backdrop nested"><section className="student-modal special-lesson-modal"><header><div><p className="eyebrow">개별 보강·추가수업</p><h2>{draft.id ? "일정 수정" : "새 일정"}</h2><span>요일 제한 없이 날짜·시간·학생을 직접 선택합니다.</span></div><button onClick={() => setDraft(null)}>×</button></header>
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
