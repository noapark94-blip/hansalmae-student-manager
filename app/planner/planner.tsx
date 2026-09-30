"use client";
import { useEffect, useRef, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  capacityProblems,
  metrics,
  validate,
  type Config,
  type Course,
  type Candidate,
  type Meeting,
  type Student,
} from "./engine";
import styles from "./planner.module.css";
import { PlacementBoard } from "./placement-board";
import { appConfirm } from "../app-dialog";
import { CourseSelection } from "./course-selection";
type Source = {
  version: string;
  classes: Omit<Course, "count" | "duration" | "enabled" | "high">[];
  teachers: { id: string; name: string }[];
};
type Draft = {
  id: string;
  title: string;
  starts_on: string;
  version: number;
  applied_at: string | null;
  payload: { config: Config; meetings: Meeting[]; sourceVersion: string };
};
const days = ["월", "화", "수", "목", "금", "토", "일"];
function defaults(s: Source): Config {
  return {
    courses: s.classes.map((c) => ({
      ...c,
      count: c.subject.includes("국어") || c.subject.includes("기하") ? 2 : 3,
      duration: 120,
      enabled:
        !c.name.includes("고3") &&
        !(c.students.length > 0 && c.students.every((s) => s.grade === "고3")),
      high:
        c.students.some((s) => s.grade.includes("고")) || c.name.includes("고"),
    })),
    teachers: s.teachers.map((t) => ({
      ...t,
      days: [1, 2, 3, 4, 5, 6, 7],
    })),
    starts: [
      "16:00,18:00,20:00",
      "18:00,20:00",
      "16:00,18:00,20:00",
      "18:00,20:00",
      "16:00,18:00,20:00",
      "09:30,11:30,14:00,16:00,18:00",
      "",
    ],
    objective: "student",
  };
}
export function TimetablePlanner({ supabase }: { supabase: SupabaseClient }) {
  const [source, setSource] = useState<Source | null>(null),
    [config, setConfig] = useState<Config | null>(null),
    [title, setTitle] = useState("11월 정규수업 편성"),
    [date, setDate] = useState("2026-11-01");
  const [draft, setDraft] = useState<Draft | null>(null),
    [drafts, setDrafts] = useState<Draft[]>([]),
    [candidates, setCandidates] = useState<Candidate[]>([]),
    [selected, setSelected] = useState(0),
    [tab, setTab] = useState<"conditions" | "results" | "compare">("results");
  const [meetings, setMeetings] = useState<Meeting[]>([]);
  const [error, setError] = useState(""),
    [notice, setNotice] = useState(""),
    [busy, setBusy] = useState(false),
    [solving, setSolving] = useState(false),
    [teacherFilter, setTeacherFilter] = useState(""),
    [applyOpen, setApplyOpen] = useState(false);
  const [selectedStudent, setSelectedStudent] = useState<Student | null>(null);
  function selectStudent(student: Student) {
    setSelectedStudent(current => current?.id === student.id ? null : student);
    setTeacherFilter("");
  }
  const [undo, setUndo] = useState<{config:Config; meetings:Meeting[]}[]>([]);
  function placementChange(next:Config, rows:Meeting[]) {
    if (!config || busy || solving) return;
    setUndo(u=>[...u.slice(-19),{config,meetings:chosen?.meetings||[]}]);
    setConfig(next); setMeetings(rows); setCandidates([]); setSelected(0);
  }
  const worker = useRef<Worker | null>(null);
  const versionRef = useRef("");
  useEffect(() => {
    let active = true;
    void Promise.all([
      supabase.rpc("admin_timetable_source"),
      supabase
        .from("timetable_plans")
        .select("*")
        .order("updated_at", { ascending: false })
        .limit(30),
    ])
      .then(([a, b]) => {
        if (!active) return;
        if (a.error || b.error) {
          setError(
            a.error?.message || b.error?.message || "불러오지 못했습니다.",
          );
          return;
        }
        const s = a.data as Source;
        setSource(s);
        versionRef.current = s.version;
        setConfig(defaults(s));
        setDrafts((b.data || []) as Draft[]);
      })
      .catch((e) => {
        if (active)
          setError(
            e instanceof Error ? e.message : "정보를 불러오지 못했습니다.",
          );
      });
    return () => {
      active = false;
      worker.current?.terminate();
    };
  }, [supabase]);
  const chosen = config ? metrics(config, meetings) : undefined;
  const displayed = tab === "compare" ? candidates[selected] : chosen;
  const issues = config && chosen ? validate(config, chosen.meetings) : [];
  function change(next: Config) {
    worker.current?.terminate();
    setSolving(false);
    const rows = meetings.filter(m => next.courses.some(c => c.enabled && c.id === m.classId));
    setConfig({...next, fixed:(next.fixed || []).filter(f => rows.some(m => m.classId===f.classId && m.day===f.day && m.start===f.start && m.end===f.end))});
    setMeetings(rows);
    setUndo([]);
    setSelectedStudent(null);
    setCandidates([]);
    setSelected(0);
    setNotice("");
  }
  function run() {
    if (!config) return;
    setError("");
    setNotice("");
    setSolving(true);
    worker.current?.terminate();
    const w = new Worker(new URL("./solver.worker.ts", import.meta.url));
    worker.current = w;
    w.onmessage = (e) => {
      if (e.data.candidates.length) setCandidates(e.data.candidates);
      setSelected(0);
      setSolving(false);
      setError(e.data.problems.join("\n"));
      if (e.data.candidates.length) {
        setTab("compare");
        setNotice(
          `${e.data.candidates.length}개 후보를 찾았습니다. 탐색한 후보 중 대기시간 순으로 정렬했습니다.`,
        );
      }
      w.terminate();
    };
    w.onerror = () => {
      setError("후보를 생성하지 못했습니다. 다시 시도해 주세요.");
      setSolving(false);
      w.terminate();
    };
    w.postMessage(config);
  }
  async function save() {
    if (!config || !source) return null;
    setBusy(true);
    setError("");
    try {
      const { data, error } = await supabase.rpc("admin_save_timetable_plan", {
        p_id: draft?.applied_at ? null : draft?.id || null,
        p_title: title,
        p_starts_on: date,
        p_payload: {
          config,
          meetings: chosen?.meetings || [],
          sourceVersion: versionRef.current,
        },
        p_version: draft?.version || null,
      });
      if (error) throw error;
      const d = data as Draft;
      setDraft(d);
      setDrafts((ds) => [d, ...ds.filter((x) => x.id !== d.id)]);
      setNotice("공유 초안을 저장했습니다. 관리자·부관리자가 함께 볼 수 있으며, 실제 시간표는 아직 바뀌지 않았습니다.");
      return d;
    } catch (e) {
      setError((e as Error).message);
      return null;
    } finally {
      setBusy(false);
    }
  }
  async function removeDraft() {
    if (!draft || draft.applied_at || busy || solving) return;
    const target = draft;
    if (!await appConfirm({eyebrow: "시간표 초안 관리", title: `“${target.title}” 초안을 삭제할까요?`, copy: "저장된 편성 조건과 후보가 삭제됩니다.", notice: "실제 정규 시간표와 수업 기록에는 영향이 없습니다. 삭제 후에는 복구할 수 없습니다.", confirmLabel: "초안 삭제", tone: "danger"})) return;
    setBusy(true);
    setError("");
    try {
      const {error} = await supabase.rpc("admin_delete_timetable_plan", {p_id:target.id, p_version:target.version});
      if (error) throw error;
      setDrafts(ds => ds.filter(d => d.id !== target.id));
      setDraft(null);
      if (source) {
        const next = defaults(source);
        next.teachers = next.teachers.map(t => ({...t, days:[...(config?.teachers.find(saved => saved.id === t.id)?.days ?? t.days)]}));
        change(next);
        versionRef.current = source.version;
      }
      setMeetings([]);
      setTab("results");
      setTitle("새 시간표 편성");
      setNotice(`“${target.title}” 초안을 삭제했습니다.`);
    } catch(e) { setError((e as Error).message); }
    finally { setBusy(false); }
  }
  async function apply() {
    if (!chosen || issues.length) return;
    if (config?.courses.some(c=>c.enabled&&c.memberCourses?.length)) { setError("합반 초안은 비교·저장용입니다. 운영 클래스의 합반 구성을 확정한 뒤 새 초안으로 실제 시간표에 적용해 주세요."); return; }
    const d = await save();
    if (!d) return;
    setBusy(true);
    try {
      const { data, error } = await supabase.rpc("admin_apply_timetable_plan", {
        p_id: d.id,
        p_version: d.version,
      });
      if (error) throw error;
      setDraft(data as Draft);
      setDrafts((ds) => ds.map((x) => (x.id === d.id ? (data as Draft) : x)));
      setApplyOpen(false);
      setNotice(
        `${date}부터 적용했습니다. 이전 시간표와 수업 기록은 보존됩니다.`,
      );
      const r = await supabase.rpc("admin_timetable_source");
      if (r.data) setSource(r.data as Source);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  async function refreshDrafts() {
    setBusy(true);
    try {
      const { data, error } = await supabase.from("timetable_plans").select("*").order("updated_at", { ascending: false }).limit(30);
      if (error) throw error;
      setDrafts((data || []) as Draft[]);
      setNotice("공유 초안 목록을 갱신했습니다. 최신 내용을 열려면 초안을 다시 선택해 주세요.");
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }
  function open(d: Draft) {
    worker.current?.terminate();
    setSolving(false);
    setDraft(d);
    setUndo([]);
    setSelectedStudent(null);
    setTitle(d.title);
    setDate(d.starts_on);
    setConfig(d.payload.config);
    versionRef.current = d.payload.sourceVersion;
    setMeetings(d.payload.meetings);
    setCandidates([]);
    setSelected(0);
    setTab("results");
    setNotice(
      d.payload.sourceVersion !== source?.version
        ? "저장 이후 운영 정보가 변경되었습니다. 비교용으로 열었으며 적용 전 새 초안을 만들어 주세요."
        : "저장한 초안을 불러왔습니다.",
    );
    setError("");
  }
  const enabled = config?.courses.filter((c) => c.enabled) || [];
  return (
    <section className={styles.root}>
      <header className={styles.hero}>
        <div>
          <span className={styles.eyebrow}>ADMIN · TIMETABLE STUDIO</span>
          <h1>시간표 편성</h1>
          <p>블록으로 배정하고, 고정한 수업을 중심으로 나머지를 추천받으세요.</p>
        </div>
        <button
          disabled={!source || busy || solving}
          onClick={() => {
            if (!source) return;
            setDraft(null);
            versionRef.current = source.version;
            const next = defaults(source);
            next.teachers = next.teachers.map(t => ({...t, days: [...(config?.teachers.find(saved => saved.id === t.id)?.days ?? t.days)]}));
            change(next);
            setMeetings([]);
            setTab("results");
            setTitle("새 시간표 편성");
          }}
        >
          ＋ 새 초안
        </button>
      </header>
      {error && (
        <div className={styles.error} role="alert">
          {error}
        </div>
      )}
      {notice && (
        <div className={styles.notice} role="status">
          {notice}
        </div>
      )}
      {!config ? (
        <p className={styles.empty}>
          {error
            ? "화면을 다시 열어 주세요."
            : "클래스와 수강생 정보를 불러오고 있습니다…"}
        </p>
      ) : (
        <>
          <fieldset disabled={busy} className={styles.controls}>
            <div className={styles.topline}>
              <label>
                초안 이름
                <input
                  value={title}
                  maxLength={100}
                  onChange={(e) => setTitle(e.target.value)}
                />
              </label>
              <label>
                적용 시작일
                <input
                  type="date"
                  value={date}
                  onChange={(e) => setDate(e.target.value)}
                />
              </label>
              <button
                disabled={busy || solving || !title.trim() || !date}
                onClick={() => void save()}
              >
                {busy ? "처리 중…" : "초안 저장"}
              </button>
              <label>
                공유 초안
                <select
                  value={draft?.id || ""}
                  onChange={(e) => {
                    const d = drafts.find((d) => d.id === e.target.value);
                    if (d) open(d);
                  }}
                >
                  <option value="">초안 선택</option>
                  {drafts.map((d) => (
                    <option key={d.id} value={d.id}>
                      {d.title}
                      {d.applied_at ? " · 적용됨" : ""}
                    </option>
                  ))}
                </select>
              </label>
              <button type="button" disabled={busy || solving} onClick={() => void refreshDrafts()}>목록 새로고침</button>
              {draft && drafts.some(d => d.id === draft.id) && <button type="button" disabled={busy || solving} onClick={async () => {
                if (await appConfirm({eyebrow: "공유 초안", title: "저장된 초안을 다시 열까요?", copy: "저장하지 않은 현재 편집 내용은 사라집니다.", confirmLabel: "다시 열기"})) {
                  const latest = drafts.find(d => d.id === draft.id);
                  if (latest) open(latest);
                }
              }}>선택한 초안 다시 열기</button>}
              {draft && <div className={styles.draftActions}>{draft.applied_at ? <span>적용 이력 · 삭제 불가</span> : <button type="button" disabled={busy || solving} onClick={()=>void removeDraft()}>초안 삭제</button>}</div>}
            </div>
            <nav className={styles.tabs} aria-label="시간표 작업 화면">
              <button aria-current={tab === "results" ? "page" : undefined} onClick={() => setTab("results")}>시간표 편성</button>
              <button aria-current={tab === "conditions" ? "page" : undefined} onClick={() => setTab("conditions")}>조건·합반 설정</button>
              {candidates.length > 0 && <button aria-current={tab === "compare" ? "page" : undefined} onClick={() => setTab("compare")}>추천안 비교 <small>{candidates.length}</small></button>}
            </nav>
            {selectedStudent && <div className={styles.studentFocus} role="status"><span><b>{selectedStudent.name}</b> 학생의 수업을 표시하고 있어요</span><button type="button" onClick={()=>setSelectedStudent(null)}>강조 해제</button></div>}
            {tab === "conditions" ? (
              <div className={styles.layout}>
                <div>
                  <section className={styles.card}>
                    <div className={styles.sectionHead}>
                      <div>
                        <h2>편성할 클래스</h2>
                        <p>
                          횟수와 수업 길이를 확인하세요. 선택하지 않은 클래스의
                          실제 시간표는 유지됩니다.
                        </p>
                      </div>
                      <span>{enabled.length}개 선택</span>
                    </div>
                    <CourseSelection config={config} onChange={change} selectedStudent={selectedStudent?.id} onSelectStudent={selectStudent} />
                  </section>
                  <section className={styles.card}>
                    <h2>선생님 근무 요일</h2>
                    {capacityProblems(config).map((message) => (
                      <div className={styles.error} key={message}>
                        {message}
                      </div>
                    ))}
                    <p>
                      근무 가능한 요일만 선택해 주세요. 선택하지 않은 요일에는 수업을
                      배정하지 않습니다. 선택한 조건은 새 초안에도 유지됩니다.
                    </p>
                    {config.teachers.map((t, i) => (
                      <div className={styles.teacher} key={t.id}>
                        <b>{t.name}</b>
                        <div>
                          {days.map((d, j) => (
                            <button
                              key={d}
                              aria-pressed={t.days.includes(j + 1)}
                              onClick={() =>
                                change({
                                  ...config,
                                  teachers: config.teachers.map((v, k) =>
                                    i === k
                                      ? {
                                          ...v,
                                          days: t.days.includes(j + 1)
                                            ? t.days.filter((n) => n !== j + 1)
                                            : [...t.days, j + 1],
                                        }
                                      : v,
                                  ),
                                })
                              }
                            >
                              {d}
                            </button>
                          ))}
                        </div>
                      </div>
                    ))}
                  </section>
                </div>
                <aside>
                  <section className={styles.card}>
                    <span className={styles.eyebrow}>PLANNING RULES</span>
                    <h2>수업 시작 시간</h2>
                    <p>쉼표로 구분합니다. 예: 16:00,18:00,20:00</p>
                    {days.map((d, i) => (
                      <label className={styles.slotInput} key={d}>
                        <b>{d}</b>
                        <input
                          aria-label={`${d}요일 시작 시간`}
                          placeholder="수업 없음"
                          value={config.starts[i]}
                          onChange={(e) =>
                            change({
                              ...config,
                              starts: config.starts.map((s, j) =>
                                j === i ? e.target.value : s,
                              ),
                            })
                          }
                        />
                      </label>
                    ))}
                    <p className={styles.hint}>
                      월·수·금 16시는 중등만, 고등부와 화·목은 17시 이후에
                      배정합니다. 종료는 22시까지입니다.
                    </p>
                  </section>
                  <section className={styles.card}>
                    <h2>무엇을 우선할까요?</h2>
                    {(
                      [
                        ["student", "학생 대기시간 최소"],
                        ["teacher", "선생님 공강 최소"],
                        ["balanced", "균형 있게"],
                      ] as const
                    ).map(([v, label]) => (
                      <label className={styles.radio} key={v}>
                        <input
                          type="radio"
                          checked={config.objective === v}
                          onChange={() => change({ ...config, objective: v })}
                        />
                        {label}
                      </label>
                    ))}
                    <p className={styles.hint}>
                      실제 수강생·선생님·강의실 중복을 검사합니다. 후보 간
                      비교이며 전역 최적해를 보장하지 않습니다.
                    </p>
                    <button type="button" disabled={solving || !enabled.length} onClick={()=>setTab("results")}>편성 화면으로</button>
                    <button
                      className={styles.primary}
                      disabled={solving || !enabled.length}
                      onClick={run}
                    >
                      {solving
                        ? "조건에 맞는 조합을 찾고 있어요…"
                        : "후보 최대 5개 만들기 →"}
                    </button>
                    {solving && (
                      <button
                        onClick={() => {
                          worker.current?.terminate();
                          setSolving(false);
                        }}
                      >
                        탐색 취소
                      </button>
                    )}
                  </section>
                </aside>
              </div>
            ) : (
              <>
                {tab === "compare" && <div className={styles.candidates}>
                  {candidates.map((c, i) => (
                    <button
                      key={i}
                      aria-pressed={i === selected}
                      onClick={() => setSelected(i)}
                    >
                      <span>OPTION {String(i + 1).padStart(2, "0")}</span>
                      <h3>
                        {i === 0 ? "첫 번째 비교안" : `${i + 1}번째 비교안`}
                      </h3>
                      <dl>
                        <div>
                          <dt>학생 대기 합계</dt>
                          <dd>{c.studentWait}분</dd>
                        </div>
                        <div>
                          <dt>선생님 공강 합계</dt>
                          <dd>{c.teacherWait}분</dd>
                        </div>
                      </dl>
                      <small>주간 · 학생별/선생님별 합산</small>
                    </button>
                  ))}
                </div>}
                {displayed && (
                  <section className={styles.card}>
                    <div className={styles.sectionHead}>
                      <div>
                        <h2>{tab === "compare" ? `추천안 ${selected+1} 미리보기` : "주간 시간표"}</h2>
                        <p>
                          {tab === "compare" ? "현재 편성은 유지됩니다. 마음에 드는 안을 가져와 계속 수정하세요." : `배정 ${meetings.length} / ${enabled.reduce((n,c)=>n+c.count,0)}회 · 고정 ${(config.fixed||[]).length}회 · 미배정 ${Math.max(0,enabled.reduce((n,c)=>n+c.count,0)-meetings.length)}회`}
                        </p>
                      </div>
                      <select
                        aria-label="선생님 시간표 필터"
                        value={teacherFilter}
                        onChange={(e) => setTeacherFilter(e.target.value)}
                      >
                        <option value="">전체 선생님</option>
                        {config.teachers.map((t) => (
                          <option key={t.id} value={t.id}>
                            {t.name}
                          </option>
                        ))}
                      </select>
                    </div>
                    {tab === "compare" ? <div className={styles.mergeToolbar}>
                      <button type="button" className={styles.primary} onClick={()=>{placementChange(config,displayed.meetings);setTab("results");setNotice("추천안을 가져왔습니다. 블록을 이동해 계속 편성하세요.");}}>이 안으로 편성</button>
                      <button type="button" onClick={()=>setTab("results")}>내 편성으로 돌아가기</button>
                    </div> : <div className={styles.mergeToolbar}>
                      <button type="button" className={styles.primary} disabled={solving || !enabled.length} onClick={run}>{solving?"추천 중…":"고정 유지 · 나머지 추천"}</button>
                      {solving && <button type="button" onClick={()=>{worker.current?.terminate();setSolving(false);}}>탐색 취소</button>}
                      <button type="button" disabled={!undo.length || solving} onClick={()=>{const prev=undo[undo.length-1];setConfig(prev.config);setMeetings(prev.meetings);setCandidates([]);setUndo(u=>u.slice(0,-1));}}>되돌리기</button>
                      <button type="button" onClick={()=>setTab("conditions")}>조건·합반 설정</button>
                    </div>}
                    {tab === "results" && (()=>{const conflicts=validate({...config,courses:config.courses.map(c=>({...c,count:meetings.filter(m=>m.classId===c.id).length}))},meetings);return conflicts.length ? <div className={styles.error}>{conflicts.join("\n")}</div> : null;})()}
                    <PlacementBoard readOnly={tab === "compare" || solving} selectedStudent={selectedStudent?.id} onSelectStudent={selectStudent} config={config} meetings={displayed.meetings} teacherFilter={teacherFilter} onChange={placementChange}/>
                    <footer className={styles.footer}>
                      <p>{config.courses.some(c=>c.enabled&&c.memberCourses?.length)?"합반이 포함된 초안은 현재 저장·비교만 가능합니다. 이 화면에서 실제 정규 시간표로 적용하는 기능은 아직 지원하지 않습니다.":"초안을 저장해 두고 충분히 비교한 뒤 적용하세요."}</p>
                      <button
                        className={styles.primary}
                        disabled={
                          busy || solving || tab === "compare" || !meetings.length || issues.length > 0 || !!draft?.applied_at
                        }
                        onClick={() => config?.courses.some(c=>c.enabled&&c.memberCourses?.length) ? void save() : setApplyOpen(true)}
                      >
                        {config.courses.some(c=>c.enabled&&c.memberCourses?.length)?"초안 저장":"실제 시간표에 적용"}
                      </button>
                    </footer>
                  </section>
                )}
              </>
            )}
          </fieldset>
        </>
      )}
      {applyOpen && (
        <div
          className={styles.backdrop}
          onKeyDown={(e) => {
            if (e.key === "Escape" && !busy) setApplyOpen(false);
          }}
          onClick={(e) => {
            if (e.target === e.currentTarget && !busy) setApplyOpen(false);
          }}
        >
          <section
            className={styles.modal}
            role="dialog"
            aria-modal="true"
            aria-labelledby="planner-apply-title"
            aria-describedby="planner-apply-warning"
          >
            <h2 id="planner-apply-title">실제 정규 시간표를 변경할까요?</h2>
            <div id="planner-apply-warning" className={styles.error}>
              <strong>주의 · 실제 운영 시간표가 변경됩니다.</strong>
              <p>아래 ‘실제 시간표 변경’을 누르면 초안 저장을 넘어, 선택한 클래스의 정규수업 요일과 시간이 적용 시작일부터 변경됩니다.</p>
              <p>아직 검토 중이라면 ‘돌아가기’를 누른 뒤 ‘초안 저장’을 이용해 주세요.</p>
            </div>
            <p>
              <b>{date}</b>부터 선택한 <b>{enabled.length}개 클래스</b>의
              정규시간표가 바뀝니다.
            </p>
            <p>
              이전 시간표는 종료일을 기록해 보존합니다. 선택하지 않은 클래스는
              그대로 유지됩니다.
            </p>
            <p>
              개별 요일 배정·미래 수업 기록·관련 보강 일정이 있으면 적용을
              중단하고 안내합니다. 합반과 고3 수업 종료는 별도 클래스 관리에서
              처리해 주세요.
            </p>
            <footer>
              <button
                autoFocus
                disabled={busy}
                onClick={() => setApplyOpen(false)}
              >
                돌아가기
              </button>
              <button
                className={styles.primary}
                disabled={busy}
                onClick={() => void apply()}
              >
                {busy ? "검사·적용 중…" : "실제 시간표 변경"}
              </button>
            </footer>
          </section>
        </div>
      )}
    </section>
  );
}
