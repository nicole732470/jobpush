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
from the shared company and LCA tables. Priority v2 is deliberately
explainable:

- every company starts at `0`;
- `+1` when any filing is in SOC major group 11
  (management), 13 (business and financial operations), or 15 (computer and
  mathematical occupations);
- `+1` for a filing in the final 365 days covered by the dataset;
- `+1` when the company has at least one certified filing;
- `+1`, `+2`, or `+3` for at least 5, 25, or 100 total filings;
- industry is retained for analysis and tie-breaking, but does not add points
  because it overlaps heavily with occupation evidence.

Higher scores are crawled first. This produces 858 score-6 companies in the
current dataset, a practical first discovery batch. Within the same score, a
scheduler orders by filing recency, certified filing count, and filing volume.

## Repository layout

```text
db/migrations/       JobPush-owned schema changes
db/refresh/          repeatable data refresh SQL
docs/                architecture and scoring notes
```
