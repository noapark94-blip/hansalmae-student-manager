# Monthly attendance coverage

- Entry: 결석·보강 → 월별 수업 횟수. Default month is Korea's current month.
- Korean target 8; English target 12. Count student/subject sessions, not duration or unique students.
- Present/late attendance counts. Corrections are excluded. Special makeup/additional lessons and legacy completed makeup sessions count in the month actually taught.
- Future regular schedules respect enrollment dates, individual weekday assignments, cancellation/move exceptions and saved lesson identities. Class makeup/roster sources merge by student/class/date.
- Linked special makeup replaces its legacy representation, preventing double counting; distinct sessions are not merged just because they share a time.
- Missing past attendance is shown as 기록 확인, not a definitive shortfall. Missing historical timetables cannot be reconstructed after destructive edits; the screen explicitly calls out historical unrecorded lessons.
- Student/month/subject target adjustments are administrator-only, version-checked, and default targets remain unchanged for other months. Zero excludes a target. No existing student targets are populated by the migration.
- Staff scope is students/subjects from their classes or special/makeup lessons. Administrators see the whole academy. For a scoped student/subject, the total includes that subject's lessons across teachers.
- The absence list is counted in records (건). Absences stay in their original absence month, including linked makeup status; standalone makeup uses its lesson month. The carryover view retains incomplete absences before the selected month.
- Repeated-absence contact/counseling workflow was discussed, but is not implemented by this change.

Verification uses synthetic records in isolated PGlite and Node model tests. Never writes real student records, sends messages or changes actual tuition/expenses.

```
HSM_PGLITE_MODULE=/path/to/@electric-sql/pglite node tests/monthly-coverage/database.cjs
node --test tests/monthly-coverage/model.test.mjs
npx next build
```

Database cases: selected weekdays, future forecast, monthly boundaries, present/late, correction exclusion, completed and linked makeup deduplication, cancelled sessions, missing attendance, regular lesson identity, replacement dates, class-makeup-only students, Korean/English defaults, target isolation/version conflict and role denial. Real concurrent lock contention and authenticated browser walkthroughs are not simulated.
