"use client";
import { useEffect, useRef, useState } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  clock,
  capacityProblems,
  domains,
  metrics,
  validate,
  type Config,
  type Course,
  type Candidate,
  type Meeting,
  type Student,
} from "./engine";
import styles from "./planner.module.css";
import { StudentRoster } from "./student-roster";
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
    [tab, setTab] = useState<"conditions" | "results">("conditions");
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
  const chosen = candidates[selected];
  const issues = config && chosen ? validate(config, chosen.meetings) : [];
  function change(next: Config) {
    worker.current?.terminate();
    setSolving(false);
    setConfig(next);
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
      setCandidates(e.data.candidates);
      setSelected(0);
      setSolving(false);
      setError(e.data.problems.join("\n"));
      if (e.data.candidates.length) {
        setTab("results");
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
      setNotice("초안을 저장했습니다. 실제 시간표는 아직 바뀌지 않았습니다.");
      return d;
    } catch (e) {
      setError((e as Error).message);
      return null;
    } finally {
      setBusy(false);
    }
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
  function open(d: Draft) {
    worker.current?.terminate();
    setSolving(false);
    setDraft(d);
    setSelectedStudent(null);
    setTitle(d.title);
    setDate(d.starts_on);
    setConfig(d.payload.config);
    versionRef.current = d.payload.sourceVersion;
    setCandidates(
      d.payload.meetings.length
        ? [metrics(d.payload.config, d.payload.meetings)]
        : [],
    );
    setSelected(0);
    setTab(d.payload.meetings.length ? "results" : "conditions");
    setNotice(
      d.payload.sourceVersion !== source?.version
        ? "저장 이후 운영 정보가 변경되었습니다. 비교용으로 열었으며 적용 전 새 초안을 만들어 주세요."
        : "저장한 초안을 불러왔습니다.",
    );
    setError("");
  }
  function edit(index: number, key: string) {
    if (!config || !chosen) return;
    const [day, start, end] = key.split(":").map(Number);
    const rows = chosen.meetings.map((m, i) =>
      i === index ? { ...m, day, start, end } : m,
    );
    setCandidates((cs) =>
      cs.map((c, i) => (i === selected ? metrics(config, rows) : c)),
    );
    setNotice("시간을 조정했습니다. 저장 전 충돌 검사를 확인해 주세요.");
  }
  const enabled = config?.courses.filter((c) => c.enabled) || [];
  return (
    <section className={styles.root}>
      <header className={styles.hero}>
        <div>
          <span className={styles.eyebrow}>ADMIN · TIMETABLE STUDIO</span>
          <h1>시간표 편성</h1>
          <p>다음 학기의 좋은 흐름을, 여러 안으로 비교해 보세요.</p>
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
            setTab("conditions");
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
                저장한 초안
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
            </div>
            <nav className={styles.tabs} aria-label="편성 단계">
              <button
                aria-current={tab === "conditions" ? "step" : undefined}
                onClick={() => setTab("conditions")}
              >
                01 조건 설정
              </button>
              <button
                disabled={!candidates.length}
                aria-current={tab === "results" ? "step" : undefined}
                onClick={() => setTab("results")}
              >
                02 후보 비교·조정 <small>{candidates.length}</small>
              </button>
            </nav>
            {selectedStudent && <div className={styles.studentFocus} role="status"><span><b>{selectedStudent.name}</b> · {selectedStudent.grade} 수업 강조 중</span><button type="button" onClick={()=>setSelectedStudent(null)}>강조 해제</button></div>}
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
                <div className={styles.candidates}>
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
                </div>
                {chosen && (
                  <section className={styles.card}>
                    <div className={styles.sectionHead}>
                      <div>
                        <h2>주간 시간표</h2>
                        <p>
                          시간 선택으로 조정할 수 있습니다. 학생 등원 합계{" "}
                          {chosen.visits}회/주
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
                    {issues.length ? (
                      <div className={styles.error}>
                        {issues.map((x) => (
                          <p key={x}>{x}</p>
                        ))}
                      </div>
                    ) : (
                      <div className={styles.valid}>
                        ✓ 선택한 클래스 간 충돌 없음 · 적용 시 기존 일정까지
                        다시 검사합니다.
                      </div>
                    )}
                    <div className={styles.week}>
                      {days.map((d, day) => (
                        <div key={d} className={styles.day}>
                          <h3>
                            {d}
                            <small>요일</small>
                          </h3>
                          {chosen.meetings
                            .map((m, index) => ({ m, index }))
                            .filter(
                              ({ m }) =>
                                m.day === day + 1 &&
                                (!teacherFilter ||
                                  config.courses
                                    .find((c) => c.id === m.classId)
                                    ?.teachers.includes(teacherFilter)),
                            )
                            .sort((a, b) => a.m.start - b.m.start)
                            .map(({ m, index }) => {
                              const c = config.courses.find(
                                (c) => c.id === m.classId,
                              )!;
                              return (
                                <article key={index} className={`${styles.lesson} ${c.students.some(s=>s.id===selectedStudent?.id)?styles.studentMatch:""}`}>
                                  <time>
                                    {clock(m.start)}–{clock(m.end)}
                                  </time>
                                  <b>{c.name}</b>
                                  <small>
                                    {c.teachers
                                      .map(
                                        (id) =>
                                          config.teachers.find(
                                            (t) => t.id === id,
                                          )?.name,
                                      )
                                      .join(" · ")}
                                  </small>
                                  <small>
                                    {c.room || "강의실 미지정"} ·{" "}
                                    {c.students.length}명
                                  </small>
                                  <StudentRoster course={c} selected={selectedStudent?.id} onSelect={selectStudent}/>
                                  <select
                                    aria-label={`${c.name} ${d}요일 시간 변경`}
                                    value={`${m.day}:${m.start}:${m.end}`}
                                    onChange={(e) =>
                                      edit(index, e.target.value)
                                    }
                                  >
                                    {domains(c, config).map((s, i) => (
                                      <option
                                        key={i}
                                        value={`${s.day}:${s.start}:${s.end}`}
                                      >
                                        {days[s.day - 1]} {clock(s.start)}–
                                        {clock(s.end)}
                                      </option>
                                    ))}
                                  </select>
                                </article>
                              );
                            })}
                        </div>
                      ))}
                    </div>
                    <footer className={styles.footer}>
                      <p>{config.courses.some(c=>c.enabled&&c.memberCourses?.length)?"합반이 포함된 초안은 현재 저장·비교만 가능합니다. 이 화면에서 실제 정규 시간표로 적용하는 기능은 아직 지원하지 않습니다.":"초안을 저장해 두고 충분히 비교한 뒤 적용하세요."}</p>
                      <button
                        className={styles.primary}
                        disabled={
                          busy || issues.length > 0 || !!draft?.applied_at
                        }
                        onClick={() => config?.courses.some(c=>c.enabled&&c.memberCourses?.length) ? void save() : setApplyOpen(true)}
                      >
                        {config.courses.some(c=>c.enabled&&c.memberCourses?.length)?"합반 초안 저장":"적용 내용 확인"}
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
          >
            <h2 id="planner-apply-title">새 시간표를 적용할까요?</h2>
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
                {busy ? "검사·적용 중…" : "검사 후 적용"}
              </button>
            </footer>
          </section>
        </div>
      )}
    </section>
  );
}
