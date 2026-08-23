"use client";

import type { CSSProperties, FormEvent } from "react";
import { useCallback, useEffect, useMemo, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import type { Profile } from "./supabase";
import { reorderById, useSortableOrder } from "./use-sortable-order";
import { isMilitaryTime, MilitaryTimeInput } from "./military-time-input";
import { ClassLearningBoard } from "./class-learning-board";
import { TeacherSpecialLessons } from "./teacher-special-lessons";

type Subject = {
  id: string;
  name: string;
  mainSubject: "국어" | "영어" | "수학";
  parentId: string | null;
};
type Schedule = {
  id: string;
  weekday: number;
  startTime: string;
  endTime: string;
};
type Student = {
  id: string;
  name: string;
  school: string | null;
  grade: string | null;
};
type ClassRoom = {
  id: string;
  name: string;
  subject: string;
  subjectId: string | null;
  room: string | null;
  color: string;
  schedules: Schedule[];
  students: Student[];
};
type Named = { id: string; name: string };
type ManagedClass = {
  id: string;
  name: string;
  subject: string;
  subjectId: string | null;
  room: string | null;
  color: string;
  active: boolean;
  schedules: Schedule[];
  teachers: Named[];
  enrollmentCount: number;
  scheduleCount: number;
  lessonCount: number;
  assignmentCount: number;
};
type Workspace = { subjects: Subject[]; classes: ClassRoom[] };
type AttendanceStatus = "present" | "late" | "absent";
type DayStudent = Student & {
  status: AttendanceStatus | null;
  lateMinutes: number | null;
  absenceReason: string | null;
  note: string | null;
};
type DayData = {
  lessonId: string | null;
  examContent: string | null;
  lessonContent: string | null;
  homeworkContent: string | null;
  students: DayStudent[];
};
type RosterStudent = {
  id: string;
  name: string;
  school: string | null;
  grade: string | null;
  status: string;
  enrollments: {
    class_id: string;
    status: string;
    classes?: { name: string; subject: string } | null;
  }[];
};
type LessonHistoryItem = {
  id: string;
  lessonDate: string;
  startsAt: string;
  examContent: string | null;
  lessonContent: string | null;
  homeworkContent: string | null;
  teacherName: string;
  present: number;
  late: number;
  absent: number;
  updatedAt: string;
};
type StudentExamResult = {
  studentId: string;
  studentName: string;
  school: string | null;
  grade: string | null;
  score: string;
  maxScore: string;
  evaluation: string;
  feedback: string;
};
const weekdays = ["월", "화", "수", "목", "금", "토", "일"];
const classColors = ["#a92d68", "#4c86a8", "#c85c7d", "#df8658", "#c8952a", "#5f9074", "#7060a7", "#61676f"];
const specialLessonsId = "__teacher_special_lessons__";

export function TeacherClassWorkspace({ supabase, profile, manageOnly = false, onClassesChanged }: { supabase: SupabaseClient; profile: Profile; manageOnly?: boolean; onClassesChanged?: () => void | Promise<void> }) {
  const [data, setData] = useState<Workspace | null>(null);
  const [selectedId, setSelectedId] = useState("");
  const [date, setDate] = useState(today());
  const [day, setDay] = useState<DayData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [subjectOpen, setSubjectOpen] = useState(false);
  const [classOpen, setClassOpen] = useState(false);
  const [manageOpen, setManageOpen] = useState(false);
  const classSortable = useSortableOrder((activeId, overId) =>
    setData((current) => {
      if (!current) return current;
      const classes = reorderById(current.classes, activeId, overId);
      void supabase.rpc("save_user_class_order", {
        p_ids: classes.map((item) => item.id),
      });
      return { ...current, classes };
    }),
  );
  const load = useCallback(async () => {
    setLoading(true);
    setError("");
    const [{ data: next, error: loadError }, { data: preferences }] = await Promise.all([supabase.rpc("teacher_class_workspace"), supabase.rpc("user_list_preferences")]);
    if (loadError || !next) {
      setError("담당 클래스 정보를 불러오지 못했습니다. DB 최신 적용 여부를 확인해 주세요.");
      setLoading(false);
      return;
    }
    const workspace = next as Workspace;
    const order = (preferences as { classOrder?: string[] } | null)?.classOrder ?? [];
    workspace.classes.sort((a, b) => {
      const ai = order.indexOf(a.id),
        bi = order.indexOf(b.id);
      return (ai < 0 ? 99999 : ai) - (bi < 0 ? 99999 : bi) || a.name.localeCompare(b.name, "ko");
    });
    setData(workspace);
    setSelectedId((current) => (current === specialLessonsId || workspace.classes.some((item) => item.id === current) ? current : (workspace.classes[0]?.id ?? specialLessonsId)));
    setLoading(false);
  }, [supabase]);
  useEffect(() => {
    void load();
  }, [load]);
  const selected = data?.classes.find((item) => item.id === selectedId);
  const loadDay = useCallback(async () => {
    if (!selectedId || selectedId === specialLessonsId) return setDay(null);
    const { data: next, error: dayError } = await supabase.rpc("staff_class_day", { p_class_id: selectedId, p_date: date });
    if (dayError) setError("선택한 날짜의 출석부를 불러오지 못했습니다.");
    else setDay(next as DayData);
  }, [date, selectedId, supabase]);
  useEffect(() => {
    void loadDay();
  }, [loadDay]);
  if (loading) return <section className="panel teacher-workspace-empty">담당 클래스를 불러오는 중이에요…</section>;
  if (error && !data) return <section className="panel teacher-workspace-empty error">{error}</section>;
  return (
    <>
      <div className="teacher-home-heading">
        <div>
          <p className="eyebrow">{profile.role === "admin" ? "전체 클래스 운영" : "나의 수업 공간"}</p>
          <h1>{profile.display_name} 선생님 클래스</h1>
          <p>클래스를 선택하면 출석부와 수업 내용을 한 화면에서 기록할 수 있습니다.</p>
        </div>
        <div className="teacher-home-actions">
          <button className="secondary-button" onClick={() => setManageOpen(true)}>
            {manageOnly ? "전체 클래스 관리" : "클래스 관리"}
          </button>
          <button className="secondary-button" onClick={() => setSubjectOpen(true)}>
            ＋ 하위과목 추가
          </button>
          <button className="primary" onClick={() => setClassOpen(true)}>
            ＋ 새 클래스
          </button>
        </div>
      </div>
      {error && <p className="attendance-error">{error}</p>}
      <section className={`teacher-class-cards ${classSortable.draggingId ? "reorder-mode" : ""}`.trim()}>
        {data?.classes.map((item) => (
            <button key={item.id} {...classSortable.itemProps(item.id)} data-drag-handle className={`${selectedId === item.id ? "active" : ""} ${classSortable.draggingId === item.id ? "dragging" : ""}`.trim()} onClick={() => setSelectedId(item.id)} style={{ "--class-color": item.color } as CSSProperties} aria-label={`${item.name}. 길게 눌러 순서 이동`}>
              <i />
              <span>
                <small>{item.subject}</small>
                <b>{item.name}</b>
                <em>
                  {scheduleText(item.schedules)}
                  {item.room ? ` · ${item.room}` : ""}
                </em>
              </span>
              <strong>{item.students.length}명</strong>
            </button>
          ))}
        <button className={`teacher-special-card ${selectedId === specialLessonsId ? "active" : ""}`} onClick={() => setSelectedId(specialLessonsId)} style={{ "--class-color": "#8e888b" } as CSSProperties}>
          <i />
          <span><small>{profile.role === "admin" ? "전체 선생님 통합" : "선생님 전용"}</small><b>개별 보강·추가수업</b><em>날짜·요일·시간 제한 없이 별도 일정 관리</em></span>
          <strong>전용</strong>
        </button>
      </section>
      {selected && <ClassDayPanel supabase={supabase} classRoom={selected} date={date} onDate={setDate} day={day} onReload={loadDay} onWorkspaceReload={load} />}
      {selectedId === specialLessonsId && <TeacherSpecialLessons supabase={supabase} profile={profile} />}
      {subjectOpen && (
        <SubjectEditor
          supabase={supabase}
          subjects={data?.subjects ?? []}
          onClose={() => setSubjectOpen(false)}
          onSaved={async () => {
            setSubjectOpen(false);
            await load();
          }}
        />
      )}
      {classOpen && (
        <ClassCreator
          supabase={supabase}
          profile={profile}
          subjects={data?.subjects ?? []}
          classes={data?.classes ?? []}
          onClose={() => setClassOpen(false)}
          onSaved={async () => {
            setClassOpen(false);
            await load();
            await onClassesChanged?.();
          }}
        />
      )}
      {manageOpen && (
        <ClassManager
          supabase={supabase}
          profile={profile}
          subjects={data?.subjects ?? []}
          onClose={() => setManageOpen(false)}
          onSaved={async () => {
            await load();
            await onClassesChanged?.();
          }}
        />
      )}
    </>
  );
}

function ClassDayPanel({ supabase, classRoom, date, onDate, day, onReload, onWorkspaceReload }: { supabase: SupabaseClient; classRoom: ClassRoom; date: string; onDate: (value: string) => void; day: DayData | null; onReload: () => Promise<void>; onWorkspaceReload: () => Promise<void> }) {
  const [saving, setSaving] = useState("");
  const [error, setError] = useState("");
  const [rosterOpen, setRosterOpen] = useState(false);
  const validDay = useMemo(() => classRoom.schedules.some((item) => item.weekday === isoWeekday(date)), [classRoom.schedules, date]);
  const archive = async () => {
    if (!window.confirm(`${classRoom.name} 클래스를 운영 종료할까요?\n학생·출결·수업 기록은 보존됩니다.`)) return;
    setSaving("archive");
    const { error: archiveError } = await supabase.rpc("staff_archive_class", {
      p_class_id: classRoom.id,
    });
    if (archiveError) {
      setError(archiveError.message);
      setSaving("");
      return;
    }
    window.location.reload();
  };
  const remove = async () => {
    if (!window.confirm(`${classRoom.name} 클래스를 완전히 삭제할까요?\n기록이 하나라도 있으면 삭제되지 않습니다.`)) return;
    setSaving("delete");
    const { error: deleteError } = await supabase.rpc("admin_delete_empty_class", { p_class_id: classRoom.id });
    if (deleteError) {
      setError(deleteError.message);
      setSaving("");
      return;
    }
    window.location.reload();
  };
  return (
    <section className="panel class-day-workspace">
      <header>
        <div>
          <p className="eyebrow">{classRoom.subject}</p>
          <h2>{classRoom.name}</h2>
          <span>
            {scheduleText(classRoom.schedules)}
            {classRoom.room ? ` · ${classRoom.room}` : ""}
          </span>
        </div>
        <div className="class-header-actions">
          <label className="class-date-picker">
            <span>달력 출석부</span>
            <input type="date" value={date} onChange={(event) => onDate(event.target.value)} />
          </label>
          <button type="button" className="secondary-button" disabled={!!saving} onClick={() => void archive()}>
            운영 종료
          </button>
          <button type="button" className="danger-button" disabled={!!saving} onClick={() => void remove()}>
            완전 삭제
          </button>
        </div>
      </header>
      {!validDay && <p className="class-day-notice">선택한 날짜에는 정규 수업이 없습니다. 보강·추가수업은 클래스 목록의 회색 전용 블록에서 등록해 주세요.</p>}
      <ClassLearningBoard
        key={`${classRoom.id}-${date}`}
        supabase={supabase}
        classId={classRoom.id}
        date={date}
        onDate={onDate}
        students={
          day?.students ??
          classRoom.students.map((item) => ({
            ...item,
            status: null,
            lateMinutes: null,
            absenceReason: null,
            note: null,
          }))
        }
        validDay={validDay}
        onReload={onReload}
      />
      <div className="class-workspace-grid class-log-grid">
        <section className="class-roster-shortcut">
          <div>
            <h3>수강 학생 관리</h3>
            <p>과목·학년에 맞는 학생이 먼저 표시됩니다. 추가·제외해도 이전 기록은 보존됩니다.</p>
          </div>
          <button type="button" className="secondary-button" onClick={() => setRosterOpen(true)}>
            학생 추가·제외
          </button>
        </section>
      </div>
      {error && <p className="form-error">{error}</p>}
      {rosterOpen && (
        <ClassRosterEditor
          supabase={supabase}
          classRoom={classRoom}
          onClose={() => setRosterOpen(false)}
          onSaved={async () => {
            setRosterOpen(false);
            await onWorkspaceReload();
            await onReload();
          }}
        />
      )}
    </section>
  );
}

function StudentExamResultEditor({ supabase, classRoom, date, examTitle, onClose, onSaved }: { supabase: SupabaseClient; classRoom: ClassRoom; date: string; examTitle: string; onClose: () => void; onSaved: () => Promise<void> }) {
  const [results, setResults] = useState<StudentExamResult[]>([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  useEffect(() => {
    void (async () => {
      const { data: next, error: loadError } = await supabase.rpc("staff_exam_results_for_class_day", { p_class_id: classRoom.id, p_date: date });
      if (loadError) {
        setError(loadError.message);
        setLoading(false);
        return;
      }
      const rows = (next as StudentExamResult[]) ?? [];
      setResults(rows.map((item) => ({ ...item, score: item.score ?? "", maxScore: item.maxScore || "100", evaluation: item.evaluation ?? "", feedback: item.feedback ?? "" })));
      setLoading(false);
    })();
  }, [classRoom.id, date, supabase]);
  const update = (studentId: string, patch: Partial<StudentExamResult>) => setResults((current) => current.map((item) => (item.studentId === studentId ? { ...item, ...patch } : item)));
  const submit = async (event: FormEvent) => {
    event.preventDefault();
    setSaving(true);
    setError("");
    for (const item of results) {
      const score = item.score.trim();
      if (!score) continue;
      const maxScore = item.maxScore.trim() || "100";
      const { error: saveError } = await supabase.rpc("staff_save_exam_result", {
        p_class_id: classRoom.id,
        p_student_id: item.studentId,
        p_exam_date: date,
        p_title: examTitle,
        p_score: Number(score),
        p_max_score: Number(maxScore),
        p_evaluation: item.evaluation.trim() || null,
        p_feedback: item.feedback.trim() || null,
      });
      if (saveError) {
        setError(saveError.message);
        setSaving(false);
        return;
      }
    }
    await onSaved();
  };
  return (
    <div className="modal-backdrop">
      <form className="modal exam-results-modal" onSubmit={submit}>
        <header>
          <div>
            <p className="eyebrow">시험 성적</p>
            <h2>{classRoom.name}</h2>
            <p>{date} · {examTitle}</p>
          </div>
          <button type="button" className="modal-close" onClick={onClose}>×</button>
        </header>
        {loading ? <p className="empty-state">성적을 불러오는 중이에요…</p> : <div className="exam-result-list">{results.map((item) => <article key={item.studentId}><span><b>{item.studentName}</b><small>{[item.school,item.grade].filter(Boolean).join(" · ")}</small></span><label>원점수<input inputMode="decimal" value={item.score} onChange={(event)=>update(item.studentId,{score:event.target.value})}/></label><label>만점<input inputMode="decimal" value={item.maxScore} onChange={(event)=>update(item.studentId,{maxScore:event.target.value})}/></label><label>평가<input value={item.evaluation} onChange={(event)=>update(item.studentId,{evaluation:event.target.value})}/></label><label>피드백<input value={item.feedback} onChange={(event)=>update(item.studentId,{feedback:event.target.value})}/></label></article>)}</div>}
        {error && <p className="form-error">{error}</p>}
        <footer><button type="button" className="secondary-button" onClick={onClose}>취소</button><button className="primary" disabled={saving || loading}>{saving ? "저장 중…" : "저장"}</button></footer>
      </form>
    </div>
  );
}

function SubjectEditor({ supabase, subjects, onClose, onSaved }: { supabase: SupabaseClient; subjects: Subject[]; onClose: () => void; onSaved: () => Promise<void> }) {
  const [name, setName] = useState("");
  const [mainSubject, setMainSubject] = useState<Subject["mainSubject"]>("영어");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!name.trim()) return;
    setSaving(true);
    setError("");
    const { error: saveError } = await supabase.rpc("staff_create_subject", { p_name: name.trim(), p_main_subject: mainSubject });
    if (saveError) {
      setError(saveError.message);
      setSaving(false);
      return;
    }
    await onSaved();
  };
  return (
    <div className="modal-backdrop">
      <form className="modal subject-editor" onSubmit={submit}>
        <header>
          <div><p className="eyebrow">과목 설정</p><h2>하위과목 추가</h2><p>국어·영어·수학 아래에 세부 과목을 추가합니다.</p></div>
          <button type="button" className="modal-close" onClick={onClose}>×</button>
        </header>
        <div className="modal-body">
          <label>과목 이름<input value={name} onChange={(event)=>setName(event.target.value)} placeholder="예: 영어 독해" /></label>
          <div className="subject-main-options">{(["국어","영어","수학"] as const).map((item)=><button type="button" key={item} className={mainSubject===item?"active":""} onClick={()=>setMainSubject(item)}>{item}</button>)}</div>
          <div className="existing-subjects"><b>현재 하위과목</b>{subjects.length ? subjects.map((item)=><span key={item.id}>{item.mainSubject} · {item.name}</span>) : <span>등록된 하위과목이 없습니다.</span>}</div>
        </div>
        {error && <p className="form-error">{error}</p>}
        <footer><button type="button" className="secondary-button" onClick={onClose}>취소</button><button className="primary" disabled={saving}>{saving?"추가 중…":"추가"}</button></footer>
      </form>
    </div>
  );
}

function ClassCreator({ supabase, profile, subjects, classes, onClose, onSaved }: { supabase: SupabaseClient; profile: Profile; subjects: Subject[]; classes: ClassRoom[]; onClose: () => void; onSaved: () => Promise<void> }) {
  const [name, setName] = useState("");
  const [subjectId, setSubjectId] = useState(subjects[0]?.id ?? "");
  const [room, setRoom] = useState("");
  const [color, setColor] = useState("#a92d68");
  const [teacherIds, setTeacherIds] = useState<string[]>([profile.id]);
  const [schedules, setSchedules] = useState<{ weekdays: number[]; startTime: string; endTime: string }[]>([{ weekdays: [1], startTime: "18:00", endTime: "20:00" }]);
  const [teachers, setTeachers] = useState<Named[]>([]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  useEffect(() => {
    void (async () => {
      const { data: rows } = await supabase.rpc("staff_teacher_options");
      setTeachers((rows as Named[]) ?? []);
    })();
  }, [supabase]);
  const addSchedule = () => setSchedules((current) => [...current, { weekdays: [], startTime: "18:00", endTime: "20:00" }]);
  const updateSchedule = (index: number, patch: Partial<(typeof schedules)[number]>) => setSchedules((current) => current.map((item, idx) => (idx === index ? { ...item, ...patch } : item)));
  const submit = async (event: FormEvent) => {
    event.preventDefault();
    setSaving(true);
    setError("");
    if (!name.trim() || !subjectId || !teacherIds.length || schedules.some((item) => !item.weekdays.length || !isMilitaryTime(item.startTime) || !isMilitaryTime(item.endTime))) {
      setError("필수 정보를 모두 입력해 주세요.");
      setSaving(false);
      return;
    }
    const { error: saveError } = await supabase.rpc("staff_create_class_with_schedules", { p_name: name.trim(), p_subject_id: subjectId, p_room: room.trim() || null, p_color: color, p_teacher_ids: teacherIds, p_schedules: schedules.flatMap((item) => item.weekdays.map((weekday) => ({ weekday, start_time: item.startTime, end_time: item.endTime }))) });
    if (saveError) {
      setError(saveError.message);
      setSaving(false);
      return;
    }
    await onSaved();
  };
  return (
    <div className="modal-backdrop">
      <form className="modal class-creator" onSubmit={submit}>
        <header><div><p className="eyebrow">나의 수업 공간</p><h2>새 클래스</h2><p>같은 시간의 요일은 함께 고르고, 시간이 다르면 묶음을 추가하세요.</p></div><button type="button" className="modal-close" onClick={onClose}>×</button></header>
        <div className="modal-body">
          <div className="form-grid"><label>클래스 이름 *<input value={name} onChange={(event)=>setName(event.target.value)} placeholder="예: 고2 영어 서해" /></label><label>과목 *<select value={subjectId} onChange={(event)=>setSubjectId(event.target.value)}>{subjects.map((item)=><option value={item.id} key={item.id}>{item.name}</option>)}</select></label><label>강의실<input value={room} onChange={(event)=>setRoom(event.target.value)} placeholder="예: A 강의실" /></label><label>표시 색상<ClassColorPicker value={color} onChange={setColor} classes={classes}/></label></div>
          <fieldset className="teacher-picker"><legend>담당 선생님 * <small>공동 담당 가능</small></legend><div>{teachers.map((item)=><label key={item.id} className={teacherIds.includes(item.id)?"active":""}><input type="checkbox" checked={teacherIds.includes(item.id)} onChange={()=>setTeacherIds((current)=>current.includes(item.id)?current.filter((id)=>id!==item.id):[...current,item.id])}/><i>{item.name.slice(0,1)}</i><span>{item.name}</span></label>)}</div></fieldset>
          <fieldset className="schedule-builder"><legend>수업 요일·시간 *</legend>{schedules.map((item,index)=><div className="schedule-row" key={index}><b className="schedule-field-title weekday-title">요일</b><b className="schedule-field-title start-title">시작</b><b className="schedule-field-title end-title">종료</b><div className="weekday-options">{weekdays.map((label,dayIndex)=><button type="button" key={label} className={item.weekdays.includes(dayIndex+1)?"active":""} onClick={()=>updateSchedule(index,{weekdays:item.weekdays.includes(dayIndex+1)?item.weekdays.filter((day)=>day!==dayIndex+1):[...item.weekdays,dayIndex+1]})}>{label}</button>)}</div><div className="schedule-time-input"><MilitaryTimeInput value={item.startTime} onChange={(value)=>updateSchedule(index,{startTime:value})}/></div><span aria-hidden="true">→</span><div className="schedule-time-input"><MilitaryTimeInput value={item.endTime} onChange={(value)=>updateSchedule(index,{endTime:value})}/></div>{schedules.length>1&&<button type="button" className="danger-link" onClick={()=>setSchedules((current)=>current.filter((_,idx)=>idx!==index))}>삭제</button>}</div>)}<small className="schedule-time-hint">시간은 24시간제 4자리로 입력해 주세요. 예: 1800</small><button type="button" className="add-schedule-row" onClick={addSchedule}>＋ 다른 시간 추가</button></fieldset>
        </div>
        {error && <p className="form-error">{error}</p>}
        <footer><button type="button" className="secondary-button" onClick={onClose}>취소</button><button className="primary" disabled={saving}>{saving?"저장 중…":"클래스 생성"}</button></footer>
      </form>
    </div>
  );
}

function ClassManager({ supabase, profile, subjects, onClose, onSaved }: { supabase: SupabaseClient; profile: Profile; subjects: Subject[]; onClose: () => void; onSaved: () => Promise<void> }) {
  const [classes,setClasses]=useState<ManagedClass[]>([]);
  const [loading,setLoading]=useState(true);
  const [editing,setEditing]=useState<ManagedClass|null>(null);
  const [error,setError]=useState("");
  const load=useCallback(async()=>{setLoading(true);setError("");const{data:rows,error:loadError}=await supabase.rpc("staff_manage_classes");if(loadError)setError(loadError.message);else setClasses((rows as ManagedClass[])??[]);setLoading(false)},[supabase]);
  useEffect(()=>{void load()},[load]);
  return <div className="modal-backdrop"><div className="modal class-manager-modal"><header><div><p className="eyebrow">전체 클래스</p><h2>클래스 관리</h2><p>클래스를 수정하거나 운영 종료할 수 있습니다.</p></div><button className="modal-close" onClick={onClose}>×</button></header><div className="modal-body">{loading?<p className="empty-state">클래스를 불러오는 중이에요…</p>:<div className="managed-class-list">{classes.map((item)=><button type="button" key={item.id} onClick={()=>setEditing(item)}><i style={{background:item.color}}/><span><b>{item.name}</b><small>{item.subject} · {item.teachers.map((teacher)=>teacher.name).join(", ")||"담당 미정"}</small><em>{item.schedules.length?scheduleText(item.schedules):"시간 미배정"}</em></span><strong>{item.enrollmentCount}명</strong></button>)}</div>}{error&&<p className="form-error">{error}</p>}</div><footer><button className="primary" onClick={onClose}>완료</button></footer>{editing&&<ClassEditor supabase={supabase} profile={profile} subjects={subjects} classes={classes} classRoom={editing} onClose={()=>setEditing(null)} onSaved={async()=>{setEditing(null);await load();await onSaved()}}/>}</div></div>
}

function ClassEditor({ supabase, profile, subjects, classes, classRoom, onClose, onSaved }: { supabase: SupabaseClient; profile: Profile; subjects: Subject[]; classes: ManagedClass[]; classRoom: ManagedClass; onClose: () => void; onSaved: () => Promise<void> }) {
  const [name,setName]=useState(classRoom.name),[subjectId,setSubjectId]=useState(classRoom.subjectId??""),[room,setRoom]=useState(classRoom.room??""),[color,setColor]=useState(classRoom.color),[teacherIds,setTeacherIds]=useState(classRoom.teachers.map((item)=>item.id)),[teachers,setTeachers]=useState<Named[]>([]),[schedules,setSchedules]=useState<{weekdays:number[];startTime:string;endTime:string}[]>(groupSchedules(classRoom.schedules)),[saving,setSaving]=useState(false),[error,setError]=useState("");
  useEffect(()=>{void(async()=>{const{data:rows}=await supabase.rpc("staff_teacher_options");setTeachers((rows as Named[])??[])})()},[supabase]);
  const updateSchedule=(index:number,patch:Partial<(typeof schedules)[number]>)=>setSchedules((current)=>current.map((item,idx)=>idx===index?{...item,...patch}:item));
  const submit=async(event:FormEvent)=>{event.preventDefault();setSaving(true);setError("");if(!name.trim()||!subjectId||!teacherIds.length||schedules.some((item)=>!item.weekdays.length||!isMilitaryTime(item.startTime)||!isMilitaryTime(item.endTime))){setError("필수 정보를 모두 입력해 주세요.");setSaving(false);return}const{error:saveError}=await supabase.rpc("staff_update_class_with_teachers",{p_class_id:classRoom.id,p_name:name.trim(),p_subject_id:subjectId,p_room:room.trim()||null,p_color:color,p_teacher_ids:teacherIds,p_schedules:schedules.flatMap((item)=>item.weekdays.map((weekday)=>({weekday,start_time:item.startTime,end_time:item.endTime})))});if(saveError){setError(saveError.message);setSaving(false);return}await onSaved()};
  return <div className="nested-modal-backdrop"><form className="modal class-creator" onSubmit={submit}><header><div><p className="eyebrow">클래스 수정</p><h2>{classRoom.name}</h2><p>기본 정보·담당 선생님·정규 수업 시간을 함께 수정합니다.</p></div><button type="button" className="modal-close" onClick={onClose}>×</button></header><div className="modal-body"><div className="form-grid"><label>클래스 이름 *<input value={name} onChange={(e)=>setName(e.target.value)}/></label><label>과목 *<select value={subjectId} onChange={(e)=>setSubjectId(e.target.value)}>{subjects.map((item)=><option value={item.id} key={item.id}>{item.name}</option>)}</select></label><label>강의실<input value={room} onChange={(e)=>setRoom(e.target.value)}/></label><label>표시 색상<ClassColorPicker value={color} onChange={setColor} classes={classes} excludeClassId={classRoom.id}/></label></div><fieldset className="teacher-picker"><legend>담당 선생님 * <small>공동 담당 가능</small></legend><div>{teachers.map((item)=><label key={item.id} className={teacherIds.includes(item.id)?"active":""}><input type="checkbox" checked={teacherIds.includes(item.id)} onChange={()=>setTeacherIds((current)=>current.includes(item.id)?current.filter((id)=>id!==item.id):[...current,item.id])}/><i>{item.name.slice(0,1)}</i><span>{item.name}</span></label>)}</div></fieldset><fieldset className="schedule-builder"><legend>수업 요일·시간 *</legend>{schedules.map((item,index)=><div className="schedule-row" key={index}><b className="schedule-field-title weekday-title">요일</b><b className="schedule-field-title start-title">시작</b><b className="schedule-field-title end-title">종료</b><div className="weekday-options">{weekdays.map((label,dayIndex)=><button type="button" key={label} className={item.weekdays.includes(dayIndex+1)?"active":""} onClick={()=>updateSchedule(index,{weekdays:item.weekdays.includes(dayIndex+1)?item.weekdays.filter((day)=>day!==dayIndex+1):[...item.weekdays,dayIndex+1]})}>{label}</button>)}</div><div className="schedule-time-input"><MilitaryTimeInput value={item.startTime} onChange={(value)=>updateSchedule(index,{startTime:value})}/></div><span aria-hidden="true">→</span><div className="schedule-time-input"><MilitaryTimeInput value={item.endTime} onChange={(value)=>updateSchedule(index,{endTime:value})}/></div>{schedules.length>1&&<button type="button" className="danger-link" onClick={()=>setSchedules((current)=>current.filter((_,idx)=>idx!==index))}>삭제</button>}</div>)}<small className="schedule-time-hint">시간은 24시간제 4자리로 입력해 주세요. 예: 1800</small><button type="button" className="add-schedule-row" onClick={()=>setSchedules((current)=>[...current,{weekdays:[],startTime:"18:00",endTime:"20:00"}])}>＋ 다른 시간 추가</button></fieldset></div>{error&&<p className="form-error">{error}</p>}<footer><button type="button" className="secondary-button" onClick={onClose}>취소</button><button className="primary" disabled={saving}>{saving?"저장 중…":"수정 저장"}</button></footer></form></div>
}

function ClassColorPicker({value,onChange,classes,excludeClassId}:{value:string;onChange:(value:string)=>void;classes:Array<{id:string;color:string}>;excludeClassId?:string}){
  const usage=useMemo(()=>{const counts=new Map<string,number>();classes.forEach((item)=>{if(item.id===excludeClassId)return;const key=item.color.toLowerCase();counts.set(key,(counts.get(key)??0)+1)});return counts},[classes,excludeClassId]);
  return <div className="class-color-picker-field"><div className="class-color-options">{classColors.map((item)=>{const count=usage.get(item.toLowerCase())??0;return <button type="button" aria-label={`${item} 색상${count?`, ${count}개 클래스에서 사용 중`:""}`} title={count?`${count}개 클래스에서 사용 중`:"사용하지 않은 색상"} key={item} className={`${value===item?"active ":""}${count?"used":""}`.trim()} onClick={()=>onChange(item)} style={{background:item}}>{count?<i aria-hidden="true"/>:null}</button>})}<input type="color" aria-label="직접 색상 선택" value={value} onChange={(event)=>onChange(event.target.value)}/></div><small className="class-color-usage-legend"><i aria-hidden="true"/> 점이 있는 색상은 다른 클래스에서 사용 중입니다.</small></div>
}

function ClassRosterEditor({ supabase, classRoom, onClose, onSaved }: { supabase: SupabaseClient; classRoom: ClassRoom; onClose: () => void; onSaved: () => Promise<void> }) {
  const [students,setStudents]=useState<RosterStudent[]>([]),[loading,setLoading]=useState(true),[saving,setSaving]=useState(""),[query,setQuery]=useState(""),[error,setError]=useState("");
  useEffect(()=>{void(async()=>{const{data:rows,error:loadError}=await supabase.rpc("staff_students_with_enrollments");if(loadError)setError(loadError.message);else setStudents((rows as RosterStudent[])??[]);setLoading(false)})()},[supabase]);
  const enrolledIds=new Set(classRoom.students.map((item)=>item.id));
  const sorted=students.filter((item)=>item.name.includes(query.trim())||item.school?.includes(query.trim())).sort((a,b)=>scoreStudent(a,classRoom)-scoreStudent(b,classRoom)||a.name.localeCompare(b.name,"ko"));
  const toggle=async(studentId:string,currentlyEnrolled:boolean)=>{setSaving(studentId);setError("");const{error:saveError}=await supabase.rpc("staff_set_class_enrollment",{p_class_id:classRoom.id,p_student_id:studentId,p_active:!currentlyEnrolled});if(saveError)setError(saveError.message);else await onSaved();setSaving("")};
  return <div className="nested-modal-backdrop"><div className="modal roster-editor"><header><div><p className="eyebrow">수강학생 관리</p><h2>{classRoom.name}</h2><p>과목·학년 우선으로 정렬되며, 추가·제외만 사용할 수 있습니다.</p></div><button className="modal-close" onClick={onClose}>×</button></header><div className="modal-body"><input className="roster-search" value={query} onChange={(e)=>setQuery(e.target.value)} placeholder="학생 이름 또는 학교 검색"/>{loading?<p className="empty-state">학생을 불러오는 중이에요…</p>:<div className="roster-option-list">{sorted.map((item)=>{const enrolled=enrolledIds.has(item.id);return <button key={item.id} className={enrolled?"enrolled":""} disabled={saving===item.id} onClick={()=>void toggle(item.id,enrolled)}><span><b>{item.name}</b><small>{[item.school,item.grade].filter(Boolean).join(" · ")}</small></span><em>{enrolled?"제외":"추가"}</em></button>})}</div>}{error&&<p className="form-error">{error}</p>}</div><footer><button className="primary" onClick={onClose}>완료</button></footer></div></div>
}

function groupSchedules(schedules:Schedule[]){const groups=new Map<string,{weekdays:number[];startTime:string;endTime:string}>();for(const item of schedules){const key=`${item.startTime}-${item.endTime}`,existing=groups.get(key);if(existing)existing.weekdays.push(item.weekday);else groups.set(key,{weekdays:[item.weekday],startTime:item.startTime,endTime:item.endTime})}return [...groups.values()].map((item)=>({...item,weekdays:item.weekdays.sort((a,b)=>a-b)}))}
function scoreStudent(student:RosterStudent,classRoom:ClassRoom){let score=2;if(student.enrollments.some((item)=>item.classes?.subject===classRoom.subject))score-=1;if(classRoom.students.some((item)=>item.grade&&item.grade===student.grade))score-=1;return score}
function scheduleText(schedules:Schedule[]){if(!schedules.length)return "시간 미배정";return schedules.map((item)=>`${weekdays[item.weekday-1]} ${item.startTime.slice(0,5)}–${item.endTime.slice(0,5)}`).join(" · ")}
function today(){return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Seoul",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date())}
function isoWeekday(value:string){const day=new Date(`${value}T12:00:00+09:00`).getDay();return day===0?7:day}
