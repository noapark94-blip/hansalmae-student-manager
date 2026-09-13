# Family page and summary regression tests

These tests create a fresh **in-memory PGlite database**. They do not accept a URL or connect to Supabase. Fixture writes never reach the live project.

```sh
npm ci --prefix tests/family-database
npm test --prefix tests/family-database
```

The schema contains only columns needed to execute the production function definitions; enum columns use text in this fixture. This validates PostgreSQL syntax, JSON results, ownership checks, date ranges, publication rules, schedule assignments and record counts. It does not model all production triggers, indexes or RLS policies. The new RPCs independently validate the caller through the existing family ownership resolver.

Cases include 67 lesson records and 75 correction records, comparison with the previous JSON output, inclusive date boundaries, unpublished records, completed historical records without enrollment, unauthorized student IDs, invalid intervals and empty results.

The migration is additive: it creates `family_student_context` and `family_summary_snapshot`; it neither changes operational rows nor replaces existing report RPCs. Deploy the migration before the frontend. A frontend rollback can continue using the previous RPCs.

Frontend regression tests run with `node --test tests/system-audit/family*.test.mjs`. The memory cache is scoped by client, account, student and page/period, expires after two minutes, clears on authentication changes and never writes student records to browser storage. Every page visit revalidates cached content. Initial visits and uncached detail views may still display loading indicators.
