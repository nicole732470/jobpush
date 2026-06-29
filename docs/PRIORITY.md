# JobPush priority scoring

For interpretation/audit notes about what P0/P1/P2 means, how many companies
are inside/outside the enabled crawl pool, and how not to misread "outside pool"
as "not tech", see [`PRIORITY_AUDIT.md`](PRIORITY_AUDIT.md).

`jobpush.company_targets_consolidated` is the canonical crawl-priority table.
It stores one score column per evidence type, then sums them into
`priority_score`. Higher values are crawled first. The per-FEIN
`jobpush.company_targets` table remains available for audit and sponsorship
resolution, but is not the crawl queue.

Current crawl version: `priority-v8-consolidated` (set in
`db/refresh/refresh_company_targets_consolidated.sql`).

## Total formula

```text
priority_score =
    target_role_score
  + lca_count_score
  + chicago_score
  + product_role_score
  + product_manager_score
  + salary_score
  + linkedin_top_employer_score
```

Maximum possible score: **5.75**

## Crawl priority tiers (`crawl_priority_tier`)

Automated tiers on `jobpush.company_targets_consolidated`:

| Tier | Rule | Meaning |
|---|---|---|
| **P1** | `priority_score > 3` | Above 3.0 (e.g. 3.25, 4.0, 5.25) |
| **P2** | `priority_score IN (3.0, 2.5)` | Exactly 3.0 or 2.5 |
| **P3** | `priority_score > 1` below P2 | Has target-role evidence plus at least one extra signal, but lower priority |
| **P0** | Manual only | Stored in `crawl_priority_overrides`; preserved across refresh |
| *(null)* | `priority_score <= 1` or exclusion | Not in priority bands; includes one-target-LCA-only thin evidence |

`computed_crawl_priority_tier` stores the rule result. `crawl_priority_tier` is
the effective tier after applying an active manual override. Manual overrides
may promote or downgrade a company to P0, P1, P2, or P3.

P3 is tracked for coverage/review, but the production daily crawl schedule still
defaults to P0/P1/P2 unless a runner explicitly includes P3. Companies with only
`target_role_score = 1` and no extra signals are intentionally outside P3.

As of the 2026-06-29 refresh after the P3 threshold update: P0 **12**,
P1 **4,629**, P2 **14,418**, P3 **17,352**, null **32,546**.

Manual override example:

```sql
INSERT INTO jobpush.crawl_priority_overrides (
    consolidation_key, override_tier, reason, created_by
)
VALUES ('salesforce', 'P0', 'Manual highest-priority company selection', 'nicole')
ON CONFLICT (consolidation_key) DO UPDATE SET
    override_tier = EXCLUDED.override_tier,
    reason = EXCLUDED.reason,
    created_by = EXCLUDED.created_by,
    active = TRUE,
    updated_at = now();
```

After editing overrides, refresh consolidated and sync `crawl_targets`.

Current manual overrides include Salesforce and the main Cognizant US entity
at P0, Google and Alphabet/Google at P0, HERE North America at P0, Grubhub
Holdings Inc. at P0, JPMorgan Chase & Co. at P0, and LEAR CORPORATION and
Baker Hughes downgraded to P2.

| Column | Points | When it applies |
|---|---:|---|
| `target_role_score` | 0 or 1 | Company has at least one LCA filing whose `soc_code` matches an active row in `jobpush.target_soc_roles` |
| `lca_count_score` | 0 or 1 | `target_role_score = 1` **and** `lca_count > 1` |
| `chicago_score` | 0 or 0.5 | `target_role_score = 1` **and** employer city/state matches `jobpush.chicago_metro_cities` (IL only) |
| `product_role_score` | 0 or 1 | `target_role_score = 1` **and** at least one raw `job_title` matches `jobpush.product_role_title_rules` |
| `product_manager_score` | 0 or 0.25 | `target_role_score = 1` **and** at least one raw `job_title` matches Product Manager or Technical Product Manager |
| `salary_score` | 0 or 1 | `target_role_score = 1` **and** minimum valid annualized target-role salary is at least $90,000 |
| `linkedin_top_employer_score` | 0 or 1 | `target_role_score = 1` **and** any member FEIN matches LinkedIn Top Companies 2026 |
| `priority_score` | sum | Sum of all component columns above |

## Prerequisite chain

Most components only apply after the company already matches a target SOC role.

```text
target_role_score = 1
    ├── lca_count_score        (+1 if lca_count > 1)
    ├── chicago_score          (+0.5 if Chicago metro)
    ├── product_role_score     (+1 if any product-class raw job_title)
    ├── product_manager_score  (+0.25 if Product Manager or Technical Product Manager)
    ├── salary_score           (+1 if minimum valid annualized target salary >= $90,000)
    └── linkedin_top_employer_score (+1 if LinkedIn 2026 top employer match)
```

If `target_role_score = 0`, every downstream component stays 0.

## Component rules (detail)

### 1. `target_role_score` (+1)

- **Input:** `public.lca_cases.soc_code`
- **Match table:** `jobpush.target_soc_roles` (`active = true`)
- **Normalization:** `jobpush.normalize_soc_code()` — eight-digit form; missing
  extension becomes `00` (for example `15-1252` → `15125200`)
- **Rule:** `+1` when `target_role_lca_count > 0`
- **No prerequisite**
- **Explicit exclusion:** `Chief Executives` (`11101100`) is inactive and does
  not count as target-role evidence.

### 2. `lca_count_score` (+1)

- **Prerequisite:** `target_role_score = 1`
- **Input:** `public.companies.lca_count` (total filings for the FEIN)
- **Rule:** `+1` when `lca_count > 1` (at least two total LCA filings)

On 2026-06-24 we tested a narrower alternative: for companies with exactly two
filings, award no point when both titles are strict high-seniority titles (CEO,
Chief, President/VP, Director/Head/Executive, Senior Manager, or Principal).
Only 447 of 7,207 two-filing target companies (6.20%) met that condition, and
only 25 were current P1 companies (385 P2; 37 unranked). Because the effect on
the working P1 queue is small relative to the extra permanent aggregation and
rule complexity, production keeps the simple `lca_count > 1` rule. Reproducible
SQL: `db/analysis/lca_two_filing_leadership_impact.sql`.

### 3. `chicago_score` (+0.5)

- **Prerequisite:** `target_role_score = 1`
- **Input:** `employer_city`, `employer_state` on the company row
- **Match:** `jobpush.is_chicago_metro(city, state)` against
  `jobpush.chicago_metro_cities`
- **Rule:** `+0.5` when city is in the Chicago metro list and state is `IL`

Chicago metro cities: Arlington Heights, Aurora, Bolingbrook, Chicago,
Des Plaines, Downers Grove, Evanston, Glenview, Hoffman Estates, Joliet,
Mount Prospect, Naperville, Oak Brook, Orland Park, Palatine, Schaumburg,
Skokie, Tinley Park, Wheaton.

### 4. `product_role_score` (+1)

- **Prerequisite:** `target_role_score = 1`
- **Input:** raw `public.lca_cases.job_title` (not `soc_title`, not mapped titles)
- **Match:** `jobpush.is_product_role_job_title(job_title)` using
  `jobpush.product_role_title_rules`
- **Rule:** `+1` when the company has at least one matching filing
- **Full pattern list:** [`PRODUCT_ROLES.md`](PRODUCT_ROLES.md)

### 5. `product_manager_score` (+0.25)

- **Prerequisite:** `target_role_score = 1`
- **Input:** raw `public.lca_cases.job_title`
- **Match:** `jobpush.is_product_manager_job_title(job_title)` — titles whose
  product-class category is `product_manager`:
  - raw title contains `product manager`
  - raw title contains `technical product manager`
- **Rule:** `+0.25` when the company has at least one matching filing
- **Note:** This is separate from `product_role_score`. A company with only
  Project Manager filings gets `product_role_score` but not `product_manager_score`.

### 6. `salary_score` (+1)

- **Prerequisite:** `target_role_score = 1`
- **Input:** `wage_rate_of_pay_from` and `wage_unit_of_pay`, only for LCA rows
  whose SOC code matches `jobpush.target_soc_roles`
- **Annualization:** Year ×1, Month ×12, Bi-Weekly ×26, Week ×52, Hour ×2080
- **Rule:** take the minimum valid annualized target-role salary across all FEIN
  members; `+1` when that minimum is at least **$90,000**
- **Missing/invalid data:** only the five units above are valid. Invalid or
  missing salary rows are excluded from the minimum. If no valid target-role
  salary remains, the score is 0.
- **Audit fields:** `target_role_valid_salary_lca_count` and
  `target_role_invalid_salary_lca_count`
- **FY2025 Q1 correction:** 104,046 rows whose wage columns had been imported
  with positional misalignment were restored from the official DOL Q1 file.
  All 785,687 LCA rows now have a recognized wage unit, and every target-role
  company has at least one valid annualized salary. See
  [`LCA_WAGE_REPAIR.md`](LCA_WAGE_REPAIR.md).

### 7. `linkedin_top_employer_score` (+1)

- **Prerequisite:** `target_role_score = 1`
- **Input:** any consolidated member FEIN matched against LinkedIn Top Companies
  2026 list
- **Match tables:** `jobpush.linkedin_top_employer_company_matches` (built from
  `company_search_keys`, `company_aliases`, and `companies.name`)
- **Rule:** `+1` when the FEIN matches any deduplicated LinkedIn 2026 employer
- **Details:** [`LINKEDIN_TOP_EMPLOYERS.md`](LINKEDIN_TOP_EMPLOYERS.md)

## Descriptive fields (not added to `priority_score`)

| Column | Meaning |
|---|---|
| `target_role_lca_count` | How many LCA filings hit a target SOC code |
| `target_role_min_annual_salary` | Minimum valid annualized salary among target-role filings |
| `target_role_valid_salary_lca_count` | Target-role filings with usable salary and unit |
| `target_role_invalid_salary_lca_count` | Target-role filings excluded because salary/unit is invalid or missing |
| `product_role_lca_count` | How many LCA filings hit a product-class job title |
| `product_role_lca_pct` | In-company product-class share (0–100) |
| `lca_count` | Total LCA filings for the company |
| `single_lca_company` | `true` when `lca_count = 1` |
| `certified_count` | Certified LCA count |
| `last_decision_date` | Most recent LCA decision date |
| `recent_lca` | Filing within the last year of the dataset window |

## Target SOC roles

Source workbook: `outputs/job_roles_20260621/LCA_All_Job_Roles_Summary.xlsx`,
sheet `SOC标准岗位汇总`, column `是否目标`.

- **107** active target SOC codes in `jobpush.target_soc_roles`
- `Dentists, General` (`29102100`) removed in v2
- `Chief Executives` (`11101100`) excluded on 2026-06-29

### Why SOC codes instead of fuzzy raw title matching

Every raw `job_title` belongs to an LCA row that already carries `soc_code`.
When that SOC code is selected, all corresponding raw job titles are included.
This is more reliable than fuzzy text matching on raw titles alone.

## Refresh

Recompute priority scores (JobPush-only writes; reads `public.lca_cases` once):

```bash
bash db/refresh/run_refresh_pipeline.sh
```

Deploy migration 019 (creates `employer_filing_stats` + initial populate):

```bash
bash db/run_migration_019.sh
```

After editing `jobpush.target_soc_roles`, `jobpush.chicago_metro_cities`, or
`jobpush.product_role_title_rules`, rerun the full pipeline.

After LinkedIn or consolidation config changes only:

```bash
bash db/refresh/run_refresh_pipeline.sh --skip-filing-stats --skip-per-fein
```

See [`PERFORMANCE.md`](PERFORMANCE.md) for timing expectations and JobLens
safety boundaries.

## Version history

| Version | Changes |
|---|---|
| `role-only-v1` | Binary target-role match only |
| `priority-v2` | 97 SOC codes; dentist removed |
| `priority-v3` | Split into `target_role_score` + `priority_score` sum |
| `priority-v4` | Added `lca_count_score`, `chicago_score`, `product_role_score` |
| `priority-v6` | `lca_count_score` threshold lowered to `lca_count > 1`; added `product_manager_score` (+0.25) |
| `priority-v7` | Added `linkedin_top_employer_score` (+1) from LinkedIn Top Companies 2026 |
| `priority-v8-consolidated` | Canonicalized crawl priority on merged employers; added `salary_score` (+1 at $90k minimum) and gated every score on `target_role_score = 1` |

## Deduplicated target SOC codes

| Normalized SOC code | Representative selected title | Selected title variants |
|---|---|---:|
| `11102100` | General and Operations Managers | 1 |
| `11202100` | Marketing Managers | 3 |
| `11302100` | Computer and Information Systems Managers | 7 |
| `11303100` | Financial Managers | 3 |
| `11303103` | Investment Fund Managers | 1 |
| `11904100` | Architectural and Engineering Managers | 1 |
| `11919900` | Managers, All Other | 1 |
| `12125200` | Software Developers | 1 |
| `12129909` | Information Technology Project Managers | 1 |
| `12205100` | Data Scientists | 1 |
| `13108200` | Project Management Specialists | 1 |
| `13111100` | MANAGEMENT ANALYSTS | 1 |
| `13116100` | Market Research Analysts and Marketing Specialists | 8 |
| `13119900` | Business Operations Specialists, All Other | 1 |
| `13205100` | Financial and Investment Analysts | 4 |
| `13205101` | Business Intelligence Analysts | 1 |
| `13205400` | Financial Risk Specialists | 2 |
| `13209900` | Financial Specialists, All Other | 2 |
| `13209901` | Financial Quantitative Analysts | 2 |
| `15102200` | Computer Programmers, Non R&D | 1 |
| `15103400` | Software Developers, Applications, Non R&D | 1 |
| `15103500` | Software Developers, Applications, R&D | 1 |
| `15103600` | Software Developers, Systems Software, Non R&D | 1 |
| `15105200` | Computer Systems Analysts, Non R&D | 1 |
| `15105300` | Computer Systems Analysts, R&D | 1 |
| `15105400` | Computer Network Architects, Non R&D | 1 |
| `15111100` | Computer and Information Research Scientists | 1 |
| `15112100` | Computer Systems Analysts | 3 |
| `15112200` | Information Security Analysts | 1 |
| `15113100` | Computer Programmers | 1 |
| `15113200` | Software Developers, Applications | 2 |
| `15113300` | Software Developers, Systems Software | 2 |
| `15113400` | Web Developers | 1 |
| `15114100` | Database Administrators | 2 |
| `15114200` | Network and Computer Systems Administrators | 1 |
| `15114300` | Computer Network Architects | 1 |
| `15115100` | Computer User Support Specialists | 1 |
| `15115200` | Computer Network Support Specialists | 1 |
| `15119900` | Computer Occupations, All Other | 1 |
| `15119901` | Software Quality Assurance Engineers and Testers | 1 |
| `15119902` | Computer Systems Engineers/Architects | 1 |
| `15119903` | Web Administrators | 1 |
| `15119906` | Database Architects | 1 |
| `15119907` | Data Warehousing Specialists | 1 |
| `15119908` | Business Intelligence Analysts | 2 |
| `15119909` | Information Technology Project Managers | 1 |
| `15119910` | Search Marketing Strategists | 1 |
| `15121100` | Computer Systems Analysts | 5 |
| `15121109` | Computer Systems Analysts | 1 |
| `15121200` | Information Security Analysts | 2 |
| `15121700` | Computer Systems Analysts, Non R&D | 2 |
| `15121800` | Computer Systems Analysts, R&D | 1 |
| `15122100` | Computer and Information Research Scientists | 2 |
| `15123100` | Computer Network Support Specialists | 2 |
| `15123200` | Computer User Support Specialists | 1 |
| `15124100` | Computer Network Architects | 1 |
| `15124101` | Telecommunications Engineering Specialists | 1 |
| `15124200` | Database Administrators | 4 |
| `15124300` | Database Architects | 4 |
| `15124301` | Data Warehousing Specialists | 2 |
| `15124400` | Network and Computer Systems Administrators | 6 |
| `15124700` | Computer Network Architects, Non R&D | 1 |
| `15124800` | Computer Network Architects, R&D | 1 |
| `15125100` | Computer Programmers | 4 |
| `15125200` | Software Developers | 23 |
| `15125300` | Software Quality Assurance Analysts and Testers | 12 |
| `15125400` | Web Developers | 1 |
| `15125500` | Web and Digital Interface Designers | 4 |
| `15129300` | Computer Programmers, Non R&D | 1 |
| `15129400` | Computer Programmers, R&D | 1 |
| `15129500` | Software Developers, Non R&D | 5 |
| `15129600` | Software Developers, R&D | 1 |
| `15129700` | Software Quality Assurance Analysts and Testers, Non R&D | 2 |
| `15129800` | Software Quality Assurance Analysts and Testers, R&D | 1 |
| `15129900` | Computer Occupations, All Other | 10 |
| `15129901` | Web Administrators | 1 |
| `15129902` | Geographic Information Systems Technologists and Technicians | 2 |
| `15129905` | Information Security Engineers | 2 |
| `15129906` | Information Technology Project Managers | 1 |
| `15129908` | Computer Systems Engineers/Architects | 9 |
| `15129909` | Information Technology Project Managers | 7 |
| `15129950` | Computer Occupations, ALL Other | 1 |
| `15203100` | Operations Research Analysts | 3 |
| `15204100` | Statisticians | 2 |
| `15205100` | Data Scientists | 5 |
| `15205101` | Business Intelligence Analysts | 7 |
| `15205102` | Business Intelligence Analyst | 1 |
| `17125200` | Software Developers | 1 |
| `17206300` | Computer Hardware Engineers, R&D | 1 |
| `19302200` | Survey Researchers | 1 |
| `25102100` | Computer Science Teachers, Postsecondary | 1 |
| `33302106` | Intelligence Analysts | 1 |
| `40903100` | Sales Engineers | 2 |
| `41303100` | Securities, Commodities, and Financial Services Sales Agents | 1 |
| `41903100` | Sales Engineers | 2 |
| `41909900` | Sales and Related Workers, All Other | 1 |
| `43911100` | Statistical Assistants | 1 |
