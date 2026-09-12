# Correction report refresh regression checks

Run with Node 24 and the project's TypeScript dependency:

```sh
node --experimental-strip-types --test tests/correction-record/*.test.mjs tests/class-record/concurrency.test.mjs tests/class-record/live-merge.test.mjs
```

The 21 checks cover batching, deduplication, serialized reads, the existing
500-record RPC limit, hidden-tab deferral, disposal, partial-response recovery,
and preserving local edits and conflict baselines while a read/save is pending.
The refresh test transpiles the production helper to resolve its extensionless
import in Node without changing the Next.js TypeScript configuration.

Controlled result: 100 distinct report notifications repeated twice in the same
batch window produce one read of 100 records, instead of 200 per-event reads.
Notifications arriving during a read become a later serialized batch. This is
a mocked RPC-boundary count, not a production latency or two-device benchmark.

Class attendance/draft/completion/publish saves now request weekly attendance
through the existing live refresh queue only; redundant direct loadWeek calls
were removed. Makeup and other independent refresh paths remain.

Validation: all 21 checks and Next.js production build passed. The separate
class-record database suite could not start because @electric-sql/pglite is not
installed in this workspace. No database functions or schema change in this patch.
