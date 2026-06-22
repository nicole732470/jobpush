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

- `target_role_score` is +1 when any filing matches one of the 97 target SOC codes;
- `lca_count_score` is +1 when `target_role_score = 1` and `lca_count > 1`;
- `chicago_score` is +0.5 for target-role companies in the Chicago metro list (IL);
- `product_role_score` is +1 when `target_role_score = 1` and any raw `job_title`
  matches `jobpush.product_role_title_rules`;
- `product_manager_score` is +0.25 when `target_role_score = 1` and any raw
  `job_title` is Product Manager or Technical Product Manager;
- `linkedin_top_employer_score` is +1 when the company matches LinkedIn Top
  Companies 2026 (`jobpush.linkedin_top_employer_company_matches`);
- `priority_score` is the sum of all component scores.

Higher `priority_score` values are crawled first.
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
