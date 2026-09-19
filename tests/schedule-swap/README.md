# Weekly class time swaps

The entry is in the timetable's existing class assignment editor. It swaps the
start times of two saved assignments on the same weekday, retaining each lesson's
duration, schedule ID, teachers, student selections and all other weekdays.
Unsaved normal-editor fields are not included; returning restores those inputs.
The final timetable is validated in one database transaction. Shared class
conflict checks now run AFTER each statement's row updates, so both new times
are visible. Exceptions roll back both rows; checks are never disabled.
The new RPC follows the existing staff authorization and advisory-lock protocol,
locks the schedules during the swap, and compares both expected snapshots.
The authenticated SECURITY DEFINER entry is intentional: it checks auth.uid()
and is_staff(), uses an empty search_path, and denies PUBLIC/anon execution.

## Verification (no production data)

Install `@electric-sql/pglite` and `playwright` in a temporary directory, then:

```sh
HSM_PGLITE_MODULE=/path/to/node_modules/@electric-sql/pglite node tests/schedule-swap/database.cjs
HSM_PLAYWRIGHT_MODULE=/path/to/node_modules/playwright HSM_CHROMIUM_PATH=/path/to/chromium node tests/schedule-swap/browser.cjs
```

`HSM_FONT_DIR` may point to an installed `@fontsource/noto-sans-kr` for screenshots.
Database tests use an in-memory PostgreSQL fixture and existing production
function definitions captured on 2026-09-19. Browser tests extract the actual
ClassEditor and mount it with mock RPCs; they never contact Supabase.

Coverage: successful atomic swaps, unequal durations, untouched weekdays and
student assignments, rollback on teacher/room/student/correction/class conflicts,
stale times/teachers, cross-day/self swaps, midnight limits, authorization,
ordinary single-row edits, 320/390/1440px layout, RPC payloads, pending saves,
error/retry, empty state and cancellation.
