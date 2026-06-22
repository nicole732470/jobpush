# Database boundary

JobLens and JobPush use the same PostgreSQL database on AWS RDS.

| PostgreSQL object | Owner | Purpose |
|---|---|---|
| `public.companies` | JobLens/shared data | One legal employer per FEIN |
| `public.lca_cases` | JobLens/shared data | Full LCA filing facts |
| `public.company_groups` | JobLens/shared data | Optional brand/parent grouping |
| `public.company_websites` | Shared data | Verified or discovered company/career URLs |
| `jobpush.company_targets` | JobPush | Crawl candidates, evidence and priority |

The PostgreSQL schema is a namespace inside the existing database, not a
separate database. This keeps joins and foreign keys simple while giving each
repository clear migration ownership.

## Priority: role-only v1

`priority_score` is a ranking score: larger values run first.

| Evidence | Points |
|---|---:|
| Baseline | 0 |
| Any SOC 11, 13, or 15 LCA filing | +1 |
| Industry | 0 (stored for later analysis/tie-breaking) |

`single_lca_company`, recency, certified count, and total LCA count remain
stored as descriptive evidence. They do not change `priority_score`.
