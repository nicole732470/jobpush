# JobPush refresh performance

JobPush shares RDS with JobLens (`joblens-db`, `db.t4g.micro`). Long refresh
times were dominated by **multiple full scans** of `public.lca_cases` (~785k
rows) inside each priority rebuild.

Migration **019** introduces a materialized FEIN layer so LCA facts are scanned
once per rebuild cycle.

## Architecture

```text
public.lca_cases  ──(one scan)──>  jobpush.employer_filing_stats
                                           │
                    ┌──────────────────────┼──────────────────────┐
                    ▼                      ▼                      ▼
         company_targets (audit)   company_targets_consolidated (crawl)
```

| Object | Role |
|---|---|
| `jobpush.employer_filing_stats` | Per-FEIN aggregates from `lca_cases` |
| `jobpush.lca_annual_salary()` | Shared annualization for wage units |
| `refresh_employer_filing_stats.sql` | Single-pass rebuild of FEIN stats |
| `refresh_company_targets.sql` | Per-FEIN audit table (no `lca_cases` scan) |
| `refresh_company_targets_consolidated.sql` | Merged crawl queue (no `lca_cases` scan) |

Scoring semantics are unchanged (`priority-v8-consolidated`).

## Refresh commands

Full rebuild after new LCA data or wage repair:

```bash
bash db/refresh/run_refresh_pipeline.sh
```

Rule-only changes (LinkedIn terms, consolidation policies):

```bash
# rebuild matches / members first, then:
bash db/refresh/run_refresh_pipeline.sh --skip-filing-stats --skip-per-fein
```

Individual steps:

```bash
bash db/refresh/run_refresh_pipeline.sh --only filing-stats
bash db/refresh/run_refresh_pipeline.sh --only consolidated
```

Deploy migration 019 + initial populate (RDS is VPC-private; use EC2 SSM):

```bash
bash db/deploy_via_ssm.sh db/run_migration_019.sh
bash db/deploy_via_ssm.sh db/refresh/run_refresh_pipeline.sh
```

Local `bash db/run_migration_019.sh` only works from inside the VPC (e.g. EC2).

## JobLens safety boundary

JobPush optimizations **only create or write `jobpush.*` objects**. They:

- Read `public.lca_cases` and `public.companies` (same as before)
- Do **not** alter `public` table structure, indexes, or application data
- Do **not** change JobLens queries or runtime behavior

Optional shared-database improvements that require JobLens coordination are
documented separately:

- [`deploy/database/RDS_UPGRADE.md`](../deploy/database/RDS_UPGRADE.md) — instance sizing
- [`docs/JOBLENS_SHARED_INDEX_NOTES.md`](JOBLENS_SHARED_INDEX_NOTES.md) — unused `lca_cases` indexes

## Wage repair staging cleanup

After verifying consolidated `salary_score` counts post-repair:

```bash
bash db/run_migration_020.sh
```

This drops `jobpush.lca_wage_repair_stage` and `jobpush.lca_wage_repair_backup`
only.

## Expected improvement (measured on `t4g.micro`, 2026-06-22)

| Step | Before | After |
|---|---:|---:|
| `employer_filing_stats` | (part of multi-scan) | **5:23** |
| `company_targets` per-FEIN | slow multi-scan | **0:08** |
| `company_targets_consolidated` | ~15–25 min | target **1–3 min** (correlated EXISTS removed in follow-up) |
| Full pipeline | ~30 min | **~6–10 min** after consolidated fix |

Upgrading RDS to `db.t4g.small` or `db.t4g.medium` further reduces the
`employer_filing_stats` scan. Coordinate maintenance windows with JobLens.

## Ad-hoc queries

Use the TablePlus SSM tunnel (`deploy/database/open-database.command`) instead
of running heavy analytics through SSM deploy scripts.
