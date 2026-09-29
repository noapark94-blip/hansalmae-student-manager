# Timetable planner verification

Run `node --test tests/planner/*.test.mjs` from the repository root. The database suite uses the existing PGlite dependency in `tests/family-database` and synthetic schema/rows only.

Implemented: administrator source snapshot, configurable weekly frequency and duration, teacher weekdays, daily start choices, bounded worker-based candidate search, aggregate waiting comparisons, manual time changes, versioned draft saves and future-dated application. History is preserved by ending old recurring rows rather than deleting them.

Application revalidates real teachers, active enrollments, rooms and unchanged schedules in a transaction. Concurrent/stale drafts, individual schedule assignments, future recorded lessons/exceptions and related special lessons are blocked. No notification is sent by this feature.

Limits: search returns up to five feasible candidates, not a global optimum or exhaustive count. Excluding a course from a draft does not retire its live schedule. Merging classes/enrollments and ending graduating classes remain separate class-management operations. Browser verification could not run because agent-browser's daemon failed to start in the current environment; the mobile layout still needs a real browser check before claiming visual verification.
