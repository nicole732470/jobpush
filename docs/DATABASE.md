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

The PostgreSQL schema is a namespace inside the existing database, not a
separate database. This keeps joins and foreign keys simple while giving each
repository clear migration ownership.

## Priority: selected SOC roles v1

`priority_score` is a ranking score: larger values run first.

| Evidence | Points |
|---|---:|
| Baseline | 0 |
| Any LCA filing whose normalized SOC code is active in `jobpush.target_soc_roles` | +1 |
| Industry | 0 (stored for later analysis/tie-breaking) |

`single_lca_company`, recency, certified count, and total LCA count remain
stored as descriptive evidence. They do not change `priority_score`.

The 98 selected codes and normalization details are documented in
[`PRIORITY.md`](PRIORITY.md).
