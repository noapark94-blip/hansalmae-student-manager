# Schedule day reminders

Opt-in flags on academic calendar events and individual makeup/additional lessons
are saved in the same transaction as the schedule. Existing permissions and
calendar field conflict comparison remain in place. Existing schedules default off.

Only the assigned active staff account can fetch or acknowledge reminders.
The inbox contains enabled schedules from the last 30 days through today;
future/cancelled/deleted/completed schedules are excluded. Multi-day calendar
events notify on the start date. Dates and midnight timers use Asia/Seoul.

Receipts use a unique (account, source, schedule, version) key. Claiming a popup
inserts that key once, so a second device does not claim it again. Dismissing a
card keeps the reminder unread in the inbox; acknowledgement is persisted.
Meaningful schedule changes create a new version; ordinary lesson content edits
do not. Changing the recipient invalidates the former recipient's view.

One provider serves the desktop/mobile notification buttons, avoiding hidden
duplicate consumers. Reads coalesce through the existing live queue, on mount,
reconnect/focus, recipient-specific changes, and a single midnight timeout.
No new repeated polling or SMS/push delivery is added.

Validation:
- 42 focused Node tests passed, including Korean day rollover and reminder-only
  conflict changes, plus existing class/correction queues and local-edit merges.
- Next.js production build and TypeScript passed.
- reminder-rollback.sql ran against the database in a transaction followed by
  ROLLBACK. It checks opt-in, repeated popup claim, acknowledgement, recipient
  isolation/reassignment, meaningful changes, cancellation, future dates,
  disabling, deletion, special lesson save/completion, and anonymous denial.
- No actual texts were sent or real account passwords changed.
- Actual two-device delivery and desktop/mobile browser visuals are not verified.

Run the SQL only inside BEGIN/ROLLBACK against a test database or as part of the
documented rollback check; it uses existing staff/student IDs as fixtures and
must never be committed. Run Node checks with:

```sh
node --experimental-strip-types --test tests/settings-concurrency/*.test.mjs
```
