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
| `jobpush.chicago_metro_cities` | JobPush | Chicago metro city list for `chicago_score` |
| `jobpush.soc_role_title_mappings` | JobPush | Raw company job titles mapped to SOC standard roles |
| `jobpush.product_role_title_rules` | JobPush | Raw `job_title` patterns for product-class role matching |

The PostgreSQL schema is a namespace inside the existing database, not a
separate database. This keeps joins and foreign keys simple while giving each
repository clear migration ownership.

## Priority scoring

| Component | Column | Points |
|---|---|---:|
| Target SOC role match | `target_role_score` | +1 |
| LCA volume | `lca_count_score` | +1 when `target_role_score = 1` and `lca_count > 5` |
| Chicago metro employer | `chicago_score` | +0.5 when `target_role_score = 1` and city is in `jobpush.chicago_metro_cities` |
| Product-class job title | `product_role_score` | +1 when `target_role_score = 1` and raw `job_title` matches `jobpush.product_role_title_rules` |
| Total | `priority_score` | sum of component scores |

`target_role_lca_count`, `product_role_lca_count`, `product_role_lca_pct`,
`single_lca_company`, recency, certified count, and total LCA count remain
descriptive evidence fields.

The 97 selected codes and normalization details are documented in
[`PRIORITY.md`](PRIORITY.md). Product-class raw job title rules are documented in
[`PRODUCT_ROLES.md`](PRODUCT_ROLES.md).

## SOC role to raw job title mappings

`jobpush.soc_role_title_mappings` stores the workbook sheet `原始职位对应`.
Each row links a company-written LCA `raw_job_title` to a normalized SOC code and
standard SOC title. `normalized_job_title` and `soc_title` use display casing;
`raw_job_title` keeps the source value from the disclosure data.

Rebuild the checked-in CSV with:

```bash
python3 scripts/build_soc_role_title_mappings.py
```
