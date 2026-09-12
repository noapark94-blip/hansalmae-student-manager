# Class record concurrency — stage 1

The change is limited to ClassLearningBoard: draft/completion, private revision save/publish, and individual attendance buttons. Calendar/class settings realtime work is not included.

## Checks

- `node --experimental-strip-types --test tests/class-record/concurrency.test.mjs`
- `npm install --prefix /tmp/hsm-sql-test @electric-sql/pglite@0.5.8` (or a compatible installed PGlite)
- `PGLITE_MODULE=/tmp/hsm-sql-test/node_modules/@electric-sql/pglite/dist/index.js node --test tests/class-record/database.test.mjs`
- `npx tsc --noEmit`

The SQL contract tests run the actual new migration against an isolated PostgreSQL fixture. Existing application RPCs are modeled in database-fixture.sql; these tests are NOT a live Supabase integration test, a two-browser test, or a production latency benchmark. They verify stale-snapshot merge/conflict behavior, atomic failure, revision privacy, authorization boundaries, and input retention. PGlite serializes statements, so lock contention is not measured.

## Rollout gates

1. Apply the additive migration to a staging database with the current application's actual RPC definitions.
2. Exercise draft, completion, private revision/publish, attendance and exam creation using two staff browser sessions; repeat on phone.
3. Compare save latency/request counts with the current release. The new screen sends one save RPC; snapshot hydration combines five previous read calls into one request (week and categories remain separate).
4. Apply the migration before publishing the client. Existing RPCs have not been revoked because other screens use them. Older open browser tabs can still use full-record legacy writes; require staff to update before relying on the new protection. Other legacy writer screens need a separate review.
5. On a conflict, “최신 내용 비교” retains pending edits and lets the user choose current or local values before another guarded save. No automatic overwrite retry.

No production data or database definitions have been changed for these tests.

Live updates: run `node --experimental-strip-types --test tests/class-record/live-merge.test.mjs tests/correction-schedule/live-refresh.test.mjs`. Nine tests verify dirty-field baseline preservation, added/deleted roster handling, serialized/coalesced reads, hidden-tab deferral and retry behavior. Run live-database-rollback.sql inside BEGIN/ROLLBACK after the live migration; production assertions passed for signals, delta equivalence, deletion and nonstaff RLS denial.

Mounted class records subscribe only to their class/date and their class roster signal. Snapshot+week reads are batched (two RPCs), not per-student calls. Local dirty input and its original conflict baseline survive live updates; removed dirty rows remain recoverable. Class list/settings changes reconcile workspace/agenda metadata in fixed parallel requests, while the open record editor remains mounted. The class manager list also refreshes without resetting its editor.

Calendar events use one ID-batch delta RPC; focus/reconnect refreshes the year and metadata. Editor baselines remain frozen for conflict detection; note previews refresh. Identifiers/dates only are published; staff RLS restricts record signals to assigned teachers/admin. No polling interval added. Category/student/profile naming changes reconcile on focus rather than dedicated signals. Other routes such as the separate timetable hub are outside the live subscriptions. Actual two-device/mobile visual verification and end-to-end latency benchmarking remain unperformed in this environment.
