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
from the shared company and LCA tables. The initial priority is deliberately
simple and explainable:

- every company starts at `0`;
- a company receives `+1` when any filing is in SOC major group 11
  (management), 13 (business and financial operations), or 15 (computer and
  mathematical occupations);
- industry is retained for analysis and tie-breaking, but does not add points
  in version 1 because it overlaps heavily with occupation evidence.

Higher scores are crawled first. Within the same score, a scheduler can later
order by filing recency, certified filing count, and filing volume.

## Repository layout

```text
db/migrations/       JobPush-owned schema changes
db/refresh/          repeatable data refresh SQL
docs/                architecture and scoring notes
```
