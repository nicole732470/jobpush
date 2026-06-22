# LinkedIn Top Companies 2026

LinkedIn's 2026 best employer lists (US national, US city lists, and European
country lists). Source workbook:
`linkedin_top_companies_2026_us_europe.xlsx`, sheet `LinkedIn 2026 Lists`.

JobPush stores a **deduplicated** employer list (178 unique company names from
290 regional appearances) and matches them to LCA employers using brand-aware
name keys.

## Tables

| Table | Purpose |
|---|---|
| `jobpush.linkedin_top_employers_2026` | Deduplicated LinkedIn employer names |
| `jobpush.linkedin_top_employer_match_terms` | Brand / alias search keys per employer |
| `jobpush.linkedin_top_employer_company_matches` | Matched `public.companies.fein` rows |

## Matching

Matching uses three sources, in order of preference for audit:

1. `public.company_search_keys` — normalized keys already used by JobLens
2. `public.company_aliases` — alternate legal or brand spellings
3. `public.companies.name` — direct legal employer name

Name normalization: `jobpush.normalize_employer_match_key()`.

Match styles per term:

- `exact` — short brands such as `ey`, `sap`, `ibm`
- `prefix` — `amazon` matches `amazon-com-services-llc`, `jpmorgan` matches
  `jpmorgan-chase`

Brand splits:

- `Alphabet/Google` → `alphabet`, `google`
- Parentheses removed: `Boston Consulting Group (BCG)` → `boston-consulting-group`

Manual alias expansions (examples):

- `EY` → `ernst-and-young`
- `JPMorganChase` → `jpmorgan`, `jp-morgan`
- `AT&T` → `att`, `at-and-t`

## Scoring

- In the canonical consolidated crawl table,
  `linkedin_top_employer_score = 1` when `target_role_score = 1` and any member
  FEIN appears in `jobpush.linkedin_top_employer_company_matches`.
- Included in consolidated `priority_score` total (`priority-v8-consolidated`).
- The older per-FEIN `company_targets` table remains on `priority-v7` for audit.

## Maintenance

Rebuild CSV inputs from the workbook:

```bash
python3 scripts/build_linkedin_top_employers_2026.py \
  ~/Downloads/linkedin_top_companies_2026_us_europe.xlsx
```

Load and refresh matches on RDS:

```bash
bash db/run_migration_015.sh
```

To recompute only company matches after editing match terms:

```bash
psql ... -f db/refresh/rebuild_linkedin_top_employer_matches.sql
psql ... -f db/refresh/refresh_company_targets_consolidated.sql
```
