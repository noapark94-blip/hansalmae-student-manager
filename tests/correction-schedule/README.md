# Correction timetable concurrency

- `node --experimental-strip-types --test tests/correction-schedule/concurrency.test.mjs` (7 checks)
- `npx tsc --noEmit`
- `npx next build --webpack`

`database-rollback.sql` exercises the new migration with the deployed application functions. Always run inside `BEGIN; SET LOCAL statement_timeout='20s'; SET LOCAL lock_timeout='3s'; ... ROLLBACK;` and never commit the test transaction. It verifies history replacement followed by a stale disjoint edit, same-field conflicts, stale deletion, deleted-record revival prevention, stale exception creation/deletion, unrelated assistant memberships and unauthenticated rejection. These checks passed against the current database and all test changes were rolled back.

Existing schedule overlap and role checks are retained by delegating validated merged assignments to the existing save function. The successor map is private (RLS enabled, no client grants). Assistant changes are membership deltas rather than whole-table replacement. A failed edit never automatically retries with a newer baseline; comparison requires explicit choices and another save.

This is not a two-browser concurrency or visual/mobile test. Existing clients must update; legacy write RPCs remain available for compatibility. Realtime timetable propagation is not introduced by this change. Existing ESLint findings in unchanged load effects/search markup remain.
