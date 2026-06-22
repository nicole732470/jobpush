# Database boundary

JobLens and JobPush use the same PostgreSQL database on AWS RDS.

| PostgreSQL object | Owner | Purpose |
|---|---|---|
| `public.companies` | JobLens/shared data | One legal employer per FEIN |
| `public.lca_cases` | JobLens/shared data | Full LCA filing facts |
| `public.company_groups` | JobLens/shared data | Optional brand/parent grouping |
| `public.company_websites` | Shared data | Verified or discovered company/career URLs |
| `jobpush.company_targets` | JobPush | Crawl candidates, evidence and priority |
| `jobpush.target_soc_roles` | JobPush | Deduplicated SOC codes used by priority scoring |
| `jobpush.soc_role_title_mappings` | JobPush | Raw company job titles mapped to SOC standard roles |

The PostgreSQL schema is a namespace inside the existing database, not a
separate database. This keeps joins and foreign keys simple while giving each
repository clear migration ownership.

## Priority scoring

`role_match_score` stores the selected-SOC role-match component. `priority_score`
is the total crawl ranking score and currently equals `role_match_score` only.
Additional component columns will be added later.

| Component | Column | Points |
|---|---|---:|
| Baseline | `role_match_score` | 0 |
| Any LCA filing whose normalized SOC code is active in `jobpush.target_soc_roles` | `role_match_score` | +1 |
| Industry | — | 0 (stored for later analysis/tie-breaking) |

`single_lca_company`, recency, certified count, and total LCA count remain
stored as descriptive evidence. They do not change any score column yet.

The 97 selected codes and normalization details are documented in
[`PRIORITY.md`](PRIORITY.md).

## SOC role to raw job title mappings

`jobpush.soc_role_title_mappings` stores the workbook sheet `原始职位对应`.
Each row links a company-written LCA `raw_job_title` to a normalized SOC code and
standard SOC title. `normalized_job_title` and `soc_title` use display casing;
`raw_job_title` keeps the source value from the disclosure data.

Rebuild the checked-in CSV with:

```bash
python3 scripts/build_soc_role_title_mappings.py
```
