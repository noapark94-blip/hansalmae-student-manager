export type Slot = { day: number; start: number; end: number };
export type Student = { id: string; name: string; grade: string };
export type Course = {
  memberCourses?: Course[];
  id: string;
  name: string;
  subject: string;
  room: string;
  teachers: string[];
  students: Student[];
  count: number;
  duration: number;
  enabled: boolean;
  high: boolean;
};
export type Teacher = { id: string; name: string; days: number[] };
export type Config = {
  fixed?: Meeting[];
  courses: Course[];
  teachers: Teacher[];
  starts: string[];
  objective: "student" | "teacher" | "balanced";
};
export type Meeting = Slot & { classId: string };
export type Candidate = {
  meetings: Meeting[];
  studentWait: number;
  teacherWait: number;
  visits: number;
  score: number;
};
export const clock = (n: number) =>
  `${Math.floor(n / 60)
    .toString()
    .padStart(2, "0")}:${(n % 60).toString().padStart(2, "0")}`;
export function minutes(s: string) {
  const [h, m] = s.split(":").map(Number);
  return h * 60 + m;
}
const intersects = (a: string[], b: string[]) => a.some((x) => b.includes(x));
export function shared(a: Course, b: Course) {
  return (
    intersects(a.teachers, b.teachers) ||
    intersects(
      a.students.map((s) => s.id),
      b.students.map((s) => s.id),
    ) ||
    !!(a.room.trim() && a.room.replace(/\s/g, "") === b.room.replace(/\s/g, ""))
  );
}
export function domains(c: Course, config: Config): Slot[] {
  return config.starts.flatMap((times, i) =>
    times
      .split(",")
      .map((s) => s.trim())
      .filter((s) => /^(?:[01]\d|2[0-3]):[0-5]\d$/.test(s))
      .map(minutes)
      .filter(
        (t) =>
          Number.isFinite(t) &&
          t >= 0 &&
          t % 60 < 60 &&
          t + c.duration <= 1320 &&
          c.teachers.every((id) =>
            config.teachers.find((x) => x.id === id)?.days.includes(i + 1),
          ),
      )
      .map((start) => ({ day: i + 1, start, end: start + c.duration })),
  );
}
export function validate(config: Config, meetings: Meeting[]) {
  const issues: string[] = [];
  const courses = config.courses.filter((c) => c.enabled);
  const map = new Map(courses.map((c) => [c.id, c]));
  for (const c of courses) {
    const rows = meetings.filter((m) => m.classId === c.id);
    if (!c.teachers.length) issues.push(`${c.name}: 담당 선생님이 없습니다.`);
    if (rows.length !== c.count)
      issues.push(`${c.name}: 주 ${c.count}회 중 ${rows.length}회 배정`);
    if (new Set(rows.map((m) => m.day)).size !== rows.length)
      issues.push(`${c.name}: 같은 날 중복 수업`);
    for (const m of rows)
      if (
        !domains(c, config).some(
          (s) => s.day === m.day && s.start === m.start && s.end === m.end,
        )
      )
        issues.push(`${c.name}: 가능 시간 또는 수업 길이를 확인해 주세요.`);
  }
  for (let i = 0; i < meetings.length; i++) {
    const a = meetings[i],
      ca = map.get(a.classId);
    if (!ca) {
      issues.push("선택하지 않은 클래스가 포함되어 있습니다.");
      continue;
    }
    for (const b of meetings.slice(i + 1)) {
      const cb = map.get(b.classId);
      if (
        cb &&
        a.day === b.day &&
        a.start < b.end &&
        b.start < a.end &&
        shared(ca, cb)
      )
        issues.push(`${ca.name} · ${cb.name}: 학생·선생님·강의실 중복`);
    }
  }
  return [...new Set(issues)];
}
export function metrics(config: Config, meetings: Meeting[]): Candidate {
  const groups = new Map<string, Slot[]>();
  for (const m of meetings) {
    const c = config.courses.find((c) => c.id === m.classId)!;
    for (const id of [
      ...c.teachers.map((t) => "t" + t),
      ...c.students.map((s) => "s" + s.id),
    ]) {
      const key = id + ":" + m.day;
      groups.set(key, [...(groups.get(key) || []), m]);
    }
  }
  let studentWait = 0,
    teacherWait = 0,
    visits = 0;
  for (const [key, rows] of groups) {
    rows.sort((a, b) => a.start - b.start);
    let end = rows[0].end,
      gap = 0;
    for (const r of rows.slice(1)) {
      gap += Math.max(0, r.start - end);
      end = Math.max(end, r.end);
    }
    if (key[0] === "s") {
      studentWait += gap;
      visits++;
    } else teacherWait += gap;
  }
  const score =
    config.objective === "teacher"
      ? teacherWait * 5 + studentWait
      : config.objective === "student"
        ? studentWait * 5 + teacherWait
        : studentWait + teacherWait;
  return {
    meetings: meetings.map((m) => ({ ...m })),
    studentWait,
    teacherWait,
    visits,
    score,
  };
}
// The relaxed interval bound ignores class/day uniqueness, so it cannot reject a feasible plan.
export function capacityProblems(config: Config): string[] {
  return config.teachers.flatMap((t) => {
    const courses = config.courses.filter(
      (c) => c.enabled && c.teachers.includes(t.id),
    );
    const required = courses.reduce((n, c) => n + c.count, 0);
    const slots = courses.flatMap((c) => domains(c, config));
    let capacity = 0;
    for (let day = 1; day <= 7; day++) {
      let end = -1;
      for (const slot of slots
        .filter((s) => s.day === day)
        .sort((a, b) => a.end - b.end)) {
        if (slot.start >= end) {
          capacity++;
          end = slot.end;
        }
      }
    }
    return required > capacity
      ? [
          `${t.name}: 주 ${required}회가 필요하지만 가능한 시간은 최대 ${capacity}회입니다. 클래스 선택·합반 구성 또는 가능 시간을 조정해 주세요.`,
        ]
      : [];
  });
}
// Bounded randomized backtracking. Returns feasible candidates, never claims global optimality.
export function generate(config: Config, budgetMs = 10000) {
  const started = Date.now(),
    courses = config.courses.filter((c) => c.enabled),
    byId = new Map(courses.map((c) => [c.id, c]));
  const problems = courses.flatMap((c) =>
    !c.teachers.length
      ? [`${c.name}: 담당 선생님을 지정해 주세요.`]
      : new Set(domains(c, config).map((s) => s.day)).size < c.count
        ? [`${c.name}: 가능한 요일이 주 ${c.count}회보다 적습니다.`]
        : [],
  );
  problems.push(...capacityProblems(config));
  if (!courses.length) problems.push("편성할 클래스를 선택해 주세요.");
  if (problems.length) return { candidates: [] as Candidate[], problems };
  const fixed = config.fixed || [];
  const fixedIssues = validate({...config, courses: config.courses.map(c => ({...c, count: fixed.filter(m=>m.classId===c.id).length}))}, fixed);
  if (fixed.some(m=>fixed.filter(n=>n.classId===m.classId).length > (byId.get(m.classId)?.count ?? 0))) fixedIssues.push("고정한 수업이 주 횟수보다 많습니다.");
  if (fixedIssues.length) return {candidates: [] as Candidate[], problems: fixedIssues};
  const jobs = courses.flatMap((c) =>
    Array.from({ length: c.count - fixed.filter(m=>m.classId===c.id).length }, (_, i) => ({ id: c.id, i })),
  );
  const answers = new Map<string, Candidate>();
  let nodes = 0;
  for (
    let restart = 0;
    restart < 60 && Date.now() - started < budgetMs;
    restart++
  ) {
    const placed: Meeting[] = fixed.map(m=>({...m}));
    let tries = 0;
    const choices = new Map(
      courses.map((c) => [
        c.id,
        domains(c, config)
          .map((s) => ({ ...s, random: Math.random() }))
          .sort((a, b) => a.random - b.random),
      ]),
    );
    function search(left: typeof jobs): boolean {
      nodes++;
      if (++tries > 18000 || Date.now() - started >= budgetMs) return false;
      if (!left.length) return true;
      let best = left[0],
        options: Slot[] | null = null;
      for (const j of left) {
        if (left.some((k) => k.id === j.id && k.i < j.i)) continue;
        const c = byId.get(j.id)!;
        const own = placed.filter((m) => m.classId === j.id);
        const opts = choices
          .get(j.id)!
          .filter(
            (s) =>
              own.every((m) => m.day !== s.day) &&
              own.filter(m=>!fixed.some(f=>f.classId===m.classId && f.day===m.day)).every(m=>m.day < s.day) &&
              placed.every(
                (m) =>
                  m.day !== s.day ||
                  m.start >= s.end ||
                  s.start >= m.end ||
                  !shared(c, byId.get(m.classId)!),
              ),
          );
        if (!opts.length) return false;
        if (options === null || opts.length < options.length) {
          best = j;
          options = opts;
        }
      }
      for (const s of options || []) {
        placed.push({
          classId: best.id,
          day: s.day,
          start: s.start,
          end: s.end,
        });
        if (search(left.filter((j) => j !== best))) return true;
        placed.pop();
      }
      return false;
    }
    if (search(jobs)) {
      const key = placed
        .map((m) => `${m.classId}:${m.day}:${m.start}`)
        .sort()
        .join("|");
      if (!answers.has(key)) answers.set(key, metrics(config, placed));
      if (answers.size >= 15) break;
    }
  }
  return {
    candidates: [...answers.values()]
      .sort((a, b) => a.score - b.score)
      .slice(0, 5),
    problems: answers.size
      ? []
      : [
          "설정한 탐색 시간 안에 완성안을 찾지 못했습니다. 불가능하다는 뜻은 아닙니다. 가능 시간이나 제외 클래스를 조정해 주세요.",
        ],
    nodes,
  };
}
