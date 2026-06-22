# Database boundary

JobLens and JobPush use the same PostgreSQL database on AWS RDS.

| PostgreSQL object | Owner | Purpose |
|---|---|---|
| `public.companies` | JobLens/shared data | One legal employer per FEIN |
| `public.lca_cases` | JobLens/shared data | Full LCA filing facts |
| `public.company_groups` | JobLens/shared data | Optional brand/parent grouping |
| `public.company_websites` | Shared data | Verified or discovered company/career URLs |
| `jobpush.employer_filing_stats` | JobPush | Per-FEIN LCA aggregates (single-scan materialized layer) |
| `jobpush.company_targets` | JobPush | Per-FEIN audit candidates, evidence and priority |
| `jobpush.target_soc_roles` | JobPush | Deduplicated SOC codes used by priority scoring |
| `jobpush.chicago_metro_cities` | JobPush | Chicago metro city list for `chicago_score` |
| `jobpush.soc_role_title_mappings` | JobPush | Raw company job titles mapped to SOC standard roles |
| `jobpush.product_role_title_rules` | JobPush | Raw `job_title` patterns for product-class role matching |
| `jobpush.linkedin_top_employers_2026` | JobPush | Deduplicated LinkedIn Top Companies 2026 employers |
| `jobpush.linkedin_top_employer_match_terms` | JobPush | Brand/alias match keys for LinkedIn employers |
| `jobpush.linkedin_top_employer_company_matches` | JobPush | FEIN matches to LinkedIn 2026 employers |
| `jobpush.company_consolidation_groups` | JobPush | Conservative merged employer groups (2+ FEINs) |
| `jobpush.company_targets_consolidated` | JobPush | Priority scores on merged + singleton employers |
| `jobpush.crawl_targets` | JobPush | Operational P0/P1/P2 company discovery queue |
| `jobpush.career_sites` | JobPush | Real corporate/career/ATS endpoints and crawl state |
| `jobpush.career_site_discovery_runs` | JobPush | Search batch counts, errors, and estimated credits |
| `jobpush.career_site_review_queue` | JobPush | One row per unverified URL for detailed review |
| `jobpush.career_site_company_review_queue` | JobPush | One row per company with up to three candidates |
| `jobpush.lca_wage_repair_stage` | JobPush | Reloadable official FY2025 Q1 wage repair input (optional; drop via migration 020) |
| `jobpush.lca_wage_repair_backup` | JobPush | Immutable before/after audit for repaired LCA wage fields (optional; drop via migration 020) |

The PostgreSQL schema is a namespace inside the existing database, not a
separate database. This keeps joins and foreign keys simple while giving each
repository clear migration ownership.

## Priority scoring

| Component | Column | Points |
|---|---|---:|
| Target SOC role match | `target_role_score` | +1 |
| LCA volume | `lca_count_score` | +1 when `target_role_score = 1` and `lca_count > 1` |
| Chicago metro employer | `chicago_score` | +0.5 when `target_role_score = 1` and city is in `jobpush.chicago_metro_cities` |
| Product-class job title | `product_role_score` | +1 when `target_role_score = 1` and raw `job_title` matches `jobpush.product_role_title_rules` |
| Product Manager title | `product_manager_score` | +0.25 when `target_role_score = 1` and raw `job_title` is Product Manager or Technical Product Manager |
| Minimum target-role salary | `salary_score` | +1 when `target_role_score = 1` and minimum valid annualized target-role salary is at least $90,000 |
| LinkedIn Top Companies 2026 | `linkedin_top_employer_score` | +1 when `target_role_score = 1` and a member FEIN matches `jobpush.linkedin_top_employer_company_matches` |
| Total | `priority_score` | sum of component scores |

`target_role_lca_count`, target salary coverage counts,
`target_role_min_annual_salary`, `product_role_lca_count`,
`product_role_lca_pct`, `single_lca_company`, recency, certified count, and
total LCA count remain descriptive evidence fields.

The FY2025 Q1 wage repair updated values—but not schema—in shared
`public.lca_cases`. The repair is keyed by `case_number`, preserves every old
and new wage field in `jobpush.lca_wage_repair_backup`, and is documented in
[`LCA_WAGE_REPAIR.md`](LCA_WAGE_REPAIR.md). JobLens remains the owner of the
shared table.

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

## Refresh pipeline

`jobpush.employer_filing_stats` is rebuilt in one pass over `public.lca_cases`.
Downstream priority tables read from that layer instead of scanning LCA rows
again.

```bash
bash db/refresh/run_refresh_pipeline.sh          # full rebuild
bash db/run_migration_019.sh                     # deploy FEIN stats layer
```

Details: [`PERFORMANCE.md`](PERFORMANCE.md).
