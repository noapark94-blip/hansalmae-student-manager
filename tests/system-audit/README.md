# System audit fixes — 2026-09-13

Scope: administrator helper authorization, active enrollment uniqueness, family lesson visibility, Alimtalk text truncation, and repeated report queries.

## Verification

- `node --test tests/system-audit/alimtalk-preview.test.mjs`: 8 cases for fallback layout, details, absence, long text, outgoing variables, and saved history.
- `database-rollback.sql`: temporary pre-optimization reference functions compare seven daily reports and one weekly report with the optimized function. Also checks all active guardian links, a nonempty historical day, selected weekdays, role restrictions, internal RPC privileges, and the active-enrollment unique constraint. All test changes roll back.
- Existing class, special lesson, correction and settings tests: 51 passed.
- `npx next build`: passed.
- Matched warm database benchmark, three repetitions: Alimtalk list 118.00ms → 32.19ms; family dashboard calculation 11.12ms → 6.09ms. These measure database work, not browser/network latency.

The duplicate enrollment row was archived in a server-only RLS table. The original earlier enrollment remains active; lesson, attendance and exam rows were not removed. New active duplicates are rejected by a partial unique index.

Internal notification helpers remain callable by their SECURITY DEFINER callers and service_role, but not directly by browser roles. The authenticated administrator account-help workflow is retained.

The frontend preserves lesson text beyond 180 characters. Existing section-count summaries remain. Messages over the existing overall 1,000-character limit show an error and are stopped before a new send request; the server still independently checks its limit. Previously sent messages remain unchanged.

No SMS or Alimtalk was sent as part of verification. Full live login and delivery testing is not claimed.
