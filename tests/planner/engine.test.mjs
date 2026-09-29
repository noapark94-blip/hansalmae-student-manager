import { test } from "node:test";
import assert from "node:assert/strict";
import ts from "typescript";
import fs from "node:fs";
const code = ts.transpile(fs.readFileSync("app/planner/engine.ts", "utf8"), {
  target: ts.ScriptTarget.ES2022,
  module: ts.ModuleKind.ES2022,
});
const { generate, validate, metrics } = await import(
  "data:text/javascript;base64," + Buffer.from(code).toString("base64")
);
const course = (id, teacher, student, room) => ({
  id,
  name: id,
  subject: "영어",
  teachers: [teacher],
  students: [{ id: student, name: student, grade: "중2" }],
  room,
  count: 3,
  duration: 120,
  enabled: true,
  high: false,
});
const base = {
  courses: [
    course("a", "t1", "s1", "1"),
    course("b", "t2", "s1", "2"),
    course("c", "t1", "s2", "3"),
  ],
  teachers: [
    { id: "t1", name: "T1", days: [1, 2, 3, 4, 5] },
    { id: "t2", name: "T2", days: [1, 2, 3, 4, 5] },
  ],
  starts: [
    "16:00,18:00,20:00",
    "18:00,20:00",
    "16:00,18:00,20:00",
    "18:00,20:00",
    "16:00,18:00,20:00",
    "",
    "",
  ],
  objective: "student",
};
test("generated candidates honor student/teacher/room conflicts and weekly count", () => {
  const { candidates } = generate(base, 1500);
  assert.ok(candidates.length);
  for (const c of candidates) {
    assert.deepEqual(validate(base, c.meetings), []);
    assert.equal(c.meetings.length, 9);
  }
});
test("manual collision reports and daily duplicate validation", () => {
  const rows = [
    { classId: "a", day: 1, start: 960, end: 1080 },
    { classId: "b", day: 1, start: 960, end: 1080 },
  ];
  assert.ok(validate(base, rows).some((x) => x.includes("중복")));
});
test("impossible weekday count returns useful reason", () => {
  const c = structuredClone(base);
  c.teachers[0].days = [1];
  assert.ok(generate(c, 100).problems.some((x) => x.includes("요일")));
});
test("waiting is per-person gaps, adjacent sessions have zero gap", () => {
  const rows = [
    { classId: "a", day: 1, start: 960, end: 1080 },
    { classId: "b", day: 1, start: 1080, end: 1200 },
  ];
  assert.equal(metrics(base, rows).studentWait, 0);
  rows[1].start = 1140;
  rows[1].end = 1260;
  assert.equal(metrics(base, rows).studentWait, 60);
});

test("teacher capacity shortage is reported before searching", () => {
  const config = structuredClone(base);
  config.courses = Array.from({ length: 5 }, (_, i) =>
    course(String(i), "t1", String(i), String(i)),
  );
  const result = generate(config, 100);
  assert.ok(
    result.problems.some((p) => p.includes("15회") && p.includes("13회")),
  );
});
