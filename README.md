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
- The FY2025 Q1 wage repair is a documented one-time data correction against
  `public.lca_cases`; it does not change that table's schema or ownership. Old
  and corrected values are retained in `jobpush.lca_wage_repair_backup`.

## Current target tables

`jobpush.company_targets` contains one row per FEIN/company and is refreshed
from the shared company and LCA tables. It remains the audit layer. Crawl
sorting uses `jobpush.company_targets_consolidated`, which combines approved
same-brand FEINs and recomputes scoring. Scoring is deliberately explainable:

- `target_role_score` is +1 when any filing matches one of the 97 target SOC codes;
- `lca_count_score` is +1 when `target_role_score = 1` and `lca_count > 1`;
- `chicago_score` is +0.5 for target-role companies in the Chicago metro list (IL);
- `product_role_score` is +1 when `target_role_score = 1` and any raw `job_title`
  matches `jobpush.product_role_title_rules`;
- `product_manager_score` is +0.25 when `target_role_score = 1` and any raw
  `job_title` is Product Manager or Technical Product Manager;
- `salary_score` is +1 when the minimum valid annualized salary among target
  roles is at least $90,000;
- `linkedin_top_employer_score` is +1 when the company has a target role and a
  member FEIN matches LinkedIn Top Companies 2026;
- `priority_score` is the sum of all component scores.

Higher `priority_score` values are crawled first.
See [`docs/PRIORITY.md`](docs/PRIORITY.md) for the complete rule and code list.

## Repository layout

```text
db/migrations/       JobPush-owned schema changes
db/refresh/          repeatable data refresh SQL
db/repair/           guarded one-time source-data corrections
db/load/             one-time or bulk CSV loads
config/              generated CSV inputs checked into git
scripts/             data build scripts
docs/                architecture and scoring notes
```

See [`docs/LCA_WAGE_REPAIR.md`](docs/LCA_WAGE_REPAIR.md) for the FY2025 Q1
official-source repair, validation checks, and incremental salary refresh.
