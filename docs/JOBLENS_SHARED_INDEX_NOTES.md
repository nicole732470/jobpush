# Shared `public.lca_cases` index notes (JobLens coordination)

JobPush read-only analytics identified large indexes on `public.lca_cases` with
**zero sequential scans** in `pg_stat_user_indexes` at diagnosis time:

| Index (approx.) | Size |
|---|---:|
| fingerprint-related | ~97 MB |
| snapshot-related | ~50 MB |
| case_number | ~42 MB |

`idx_lca_cases_employer_fein` is actively used by JobPush filing stats and
should be kept.

## JobPush policy

JobPush **will not** drop or alter `public` indexes from its migrations or
refresh scripts. Any cleanup requires explicit JobLens team approval and should
be run manually during a maintenance window.

## Suggested verification (JobLens runs)

```sql
SELECT indexrelname, idx_scan, pg_size_pretty(pg_relation_size(indexrelid))
FROM pg_stat_user_indexes
WHERE schemaname = 'public' AND relname = 'lca_cases'
ORDER BY pg_relation_size(indexrelid) DESC;
```

Before dropping an index, confirm JobLens application queries do not depend on
it (`EXPLAIN` on hot paths).

## Safe JobPush-only cleanup

Wage repair staging tables in `jobpush` schema:

```bash
bash db/run_migration_020.sh
```
