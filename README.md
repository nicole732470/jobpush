# JobPush

JobPush discovers company career websites and monitors official job postings.
It shares the AWS RDS database with JobLens, but owns only the objects in the
PostgreSQL `jobpush` schema.

## Data ownership

- JobLens owns the shared `public.companies`, `public.lca_cases`, company alias,
  search-key, group, and website tables.
- JobPush owns `jobpush.company_targets` and future crawl/run/job-posting tables.
- JobPush reads shared company and LCA data; it does not copy the source Excel
  workbooks into GitHub.
- Only one repository may own migrations for a given table.

## Current target table

`jobpush.company_targets` contains one row per FEIN/company and is refreshed
from the shared company and LCA tables. Scoring is deliberately explainable:

- `role_match_score` is the selected-SOC role-match component;
- every company starts at `0`;
- `+1` when any filing matches one of the 97 deduplicated SOC codes selected in
  the workbook's `是否目标` column;
- `priority_score` is the total crawl ranking score and currently equals
  `role_match_score` only;
- industry is retained for analysis and tie-breaking, but does not add points
  because it overlaps heavily with occupation evidence.

Higher `priority_score` values are crawled first. Filing recency, certification,
and filing volume remain available as descriptive fields but do not affect
scoring yet.
See [`docs/PRIORITY.md`](docs/PRIORITY.md) for the complete rule and code list.

## Repository layout

```text
db/migrations/       JobPush-owned schema changes
db/refresh/          repeatable data refresh SQL
db/load/             one-time or bulk CSV loads
config/              generated CSV inputs checked into git
scripts/             data build scripts
docs/                architecture and scoring notes
```
