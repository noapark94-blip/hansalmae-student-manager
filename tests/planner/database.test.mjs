import { readFile } from "node:fs/promises";
import { test } from "node:test";
import assert from "node:assert/strict";
import { PGlite } from "../family-database/node_modules/@electric-sql/pglite/dist/index.js";
const admin = "00000000-0000-0000-0000-000000000001",
  cid = "00000000-0000-0000-0000-000000000002";
test("administrator drafts, conflict checks and history-preserving application", async (t) => {
  const db = new PGlite();
  t.after(() => db.close());
  await db.exec(
    await readFile(
      new URL("../class-participants/schema.sql", import.meta.url),
      "utf8",
    ),
  );
  await db.exec("set check_function_bodies=on");
  await db.exec(
    await readFile(
      new URL(
        "../../supabase/migrations/20260928153532_admin_timetable_planner.sql",
        import.meta.url,
      ),
      "utf8",
    ),
  );
  await db.exec(await readFile(new URL("../../supabase/migrations/20260929131518_delete_unapplied_timetable_drafts.sql", import.meta.url), "utf8"));
  await db.exec(await readFile(new URL("../../supabase/migrations/20260930124549_shared_timetable_planner_roles.sql", import.meta.url), "utf8"));
  await db.exec(
    `set test.uid='${admin}'; set test.role='admin'; insert into profiles(id,role,display_name) values('${admin}','admin','테스트'); insert into classes(id,name,subject,room) values('${cid}','중등 영어','영어','1'); insert into class_teachers(class_id,profile_id) values('${cid}','${admin}'); insert into class_schedules(class_id,weekday,start_time,end_time,valid_from) values('${cid}',1,'16:00','18:00','2020-01-01');`,
  );
  const query = async (s, p) => (await db.query(s, p)).rows[0];
  const src = (await query("select admin_timetable_source() data")).data;
  const config = {
    courses: [
      {
        ...src.classes[0],
        enabled: true,
        count: 2,
        duration: 120,
        high: true,
      },
    ],
    teachers: [{ id: admin, name: "테스트", days: [1, 3, 5] }],
    starts: ["16:00", "", "16:00", "", "16:00", "", ""],
  };
  const payload = {
    config,
    sourceVersion: src.version,
    meetings: [
      { classId: cid, day: 1, start: 960, end: 1080 },
      { classId: cid, day: 3, start: 960, end: 1080 },
    ],
  };
  const save = async (p = payload) =>
    (
      await query(
        "select admin_save_timetable_plan(null,'테스트',current_date+30,$1::jsonb,null) data",
        [JSON.stringify(p)],
      )
    ).data;
  const apply = async (d) =>
    (
      await query("select admin_apply_timetable_plan($1,$2) data", [
        d.id,
        d.version,
      ])
    ).data;
  await t.test("non-admin RPC access denied", async () => {
    await db.exec("set test.role='teacher'");
    await assert.rejects(
      () => query("select admin_timetable_source()"),
      /관리자/,
    );
    await db.exec("set test.role='admin'");
  });
  await t.test("sub-admin can share, update and delete admin drafts; other roles cannot", async () => {
    const d = await save();
    await db.exec("insert into profiles(id,role,display_name) values('00000000-0000-0000-0000-000000000009','sub_admin','부관리자'); set test.uid='00000000-0000-0000-0000-000000000009'; set test.role='sub_admin'; set role authenticated");
    assert.ok((await db.query("select id from timetable_plans where id=$1", [d.id])).rows.length);
    await query("select admin_timetable_source()");
    const updated = (await query("select admin_save_timetable_plan($1,'공유 수정',current_date+30,$2,$3) data", [d.id, JSON.stringify(payload), d.version])).data;
    await assert.rejects(() => query("select admin_save_timetable_plan($1,'충돌',current_date+30,$2,$3)", [d.id, JSON.stringify(payload), d.version]), /다른 관리자/);
    await query("select admin_delete_timetable_plan($1,$2)", [updated.id, updated.version]);
    for (const role of ['teacher', 'student', 'guardian', 'assistant', 'manager']) {
      await db.exec(`set test.role='${role}'`);
      assert.equal((await db.query("select * from timetable_plans")).rows.length, 0);
      await assert.rejects(() => query("select admin_timetable_source()"), /관리자/);
      await assert.rejects(() => save(), /관리자/);
      await assert.rejects(() => apply(d), /관리자/);
      await assert.rejects(() => query("select admin_delete_timetable_plan($1,$2)", [d.id,d.version]), /관리자/);
    }
    await db.exec(`reset role; set test.role='admin'; set test.uid='${admin}'`);
  });
  await t.test("bad days rejected without mutating schedules", async () => {
    const p = structuredClone(payload);
    p.meetings[1].day = 2;
    await assert.rejects(() => save(p).then(apply), /근무 요일/);
    assert.equal(
      (await query("select count(*)::int n from class_schedules")).n,
      1,
    );
  });
  await t.test("duplicate class day rejected", async () => {
    const p = structuredClone(payload);
    p.meetings[1].day = 1;
    await assert.rejects(() => save(p).then(apply), /여러 번/);
  });
  await t.test("stale source rejected", async () => {
    await assert.rejects(
      () => save({ ...payload, sourceVersion: "old" }).then(apply),
      /변경되었습니다/,
    );
  });
  await t.test("concurrent save version protected", async () => {
    const d = await save();
    await assert.rejects(
      () =>
        query(
          "select admin_save_timetable_plan($1,'x',current_date+30,$2,99)",
          [d.id, JSON.stringify(payload)],
        ),
      /다른 관리자/,
    );
  });
  await t.test("unchanged class sharing teacher blocks apply", async () => {
    const other = "00000000-0000-0000-0000-000000000003";
    await db.exec(
      `insert into classes(id,name,subject,room) values('${other}','기존 클래스','영어','2');insert into class_teachers(class_id,profile_id) values('${other}','${admin}');insert into class_schedules(class_id,weekday,start_time,end_time) values('${other}',1,'16:00','18:00');`,
    );
    const source = (await query("select admin_timetable_source() data")).data;
    await assert.rejects(
      () => save({ ...payload, sourceVersion: source.version }).then(apply),
      /충돌/,
    );
    await db.exec(
      `delete from class_schedules where class_id='${other}';delete from class_teachers where class_id='${other}';delete from classes where id='${other}';`,
    );
  });
  await t.test(
    "apply preserves old range and starts future range",
    async () => {
      const d = await save();
      await db.exec("set test.role='sub_admin'; set role authenticated");
      const a = await apply(d);
      await db.exec("reset role; set test.role='admin'");
      assert.ok(a.applied_at);
      const rows = (
        await db.query(
          "select valid_from,valid_until from class_schedules order by valid_from",
        )
      ).rows;
      assert.equal(rows.length, 3);
      assert.ok(rows[0].valid_until);
      assert.equal(rows[1].valid_until, null);
      await assert.rejects(() => apply(d), /이미 적용/);
    },
  );
  await t.test(
    "table write and anonymous execution privileges revoked",
    async () => {
      const r = await query(
        "select has_table_privilege('authenticated','timetable_plans','INSERT') ins, has_function_privilege('anon','admin_timetable_source()','EXECUTE') exe",
      );
      assert.equal(r.ins, false);
      assert.equal(r.exe, false);
    },
  );
});
