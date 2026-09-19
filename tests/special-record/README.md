# Mixed special lessons

The mixed lesson tests use only synthetic students in local PGlite and mocked browser RPCs. They never send messages or write production student data.

- `mixed-lessons.test.cjs`: actual migration and existing save/conflict routines; student kinds, absence linking/completion, family schedule/report queries, alimtalk labels, record preservation, stale roster rejection, duplicate booking and authorization.
- `mixed-browser.cjs`: actual editor at 320/390/1440 px; student classification, optional absence selection, existing-session join and save payload.
- `mixed-schema.sql` / `mixed-existing-functions.sql`: schema/function fixtures without production records. Unrelated family dashboard and regular-history providers are stubbed in the test.

Run with PGlite, Playwright, esbuild and Chromium installed. `HSM_PGLITE_MODULE`, `HSM_PLAYWRIGHT_MODULE`, `HSM_CHROMIUM_PATH` and optional `HSM_FONT_DIR` accept local dependency paths.

```sh
node tests/special-record/mixed-lessons.test.cjs
node tests/special-record/mixed-browser.cjs
```

Production uses the Vercel build command `npx next build`.
