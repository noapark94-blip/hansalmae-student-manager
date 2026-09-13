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

## Detail and network-error follow-up

Monthly summary clicks now carry the record date. The detail loader uses the authorized period RPC for the selected date. Previous homework is fetched by record ID through `family_previous_homework`, without a date limit, after verifying student ownership and the current record's publication. Failed/missing detail reads show a closable message. Each selected record mounts a separate detail view so late responses cannot select a previous record.

Transport errors returned as Supabase error objects preserve cached page data; recognized access-denial errors and unknown database errors clear it. Regression cases cover both returned errors and rejected promises, including the 67th lesson and 75th correction opening through the actual selection effect.

The homework lookup is tested across 90–120 day gaps, against private records and other students, and for regular/special/correction lessons. Feed retries have a dedicated initial-load test; access denial clears existing records and cache, while transport failures retain records.
