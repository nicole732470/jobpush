# JobPush priority audit notes

Last updated: 2026-06-28

This document is the interpretation/audit companion to [`PRIORITY.md`](PRIORITY.md).
`PRIORITY.md` defines the score formula. This file explains how to read the
results, especially the difference between:

- the full LCA employer universe;
- companies with target-role evidence;
- the enabled P0/P1/P2 crawl pool;
- companies outside the crawl pool.

## Canonical tables

| Table / view | Meaning |
|---|---|
| `jobpush.company_targets_consolidated` | Canonical scoring table. One row per consolidated employer/group. Contains score components and evidence fields. |
| `jobpush.crawl_targets` | Operational crawl/discovery queue. This is the actual P0/P1/P2 pool used by JobPush. |
| `jobpush.crawl_priority_overrides` | Manual promotions/downgrades, including manual P0 and manual P2 decisions. |
| `jobpush.target_soc_roles` | Active SOC codes that count as target-role LCA evidence. |

When discussing "the 20k companies", use:

```sql
SELECT priority_tier, COUNT(*) AS companies
FROM jobpush.crawl_targets
WHERE enabled AND priority_tier IN ('P0','P1','P2')
GROUP BY priority_tier
ORDER BY priority_tier;
```

## Current crawl pool snapshot

As of 2026-06-28:

| Tier | Companies |
|---|---:|
| P0 | 10 |
| P1 | 4,634 |
| P2 | 14,470 |
| **Total enabled P0/P1/P2** | **19,114** |

This is the current operational JobPush crawl pool. It is the set we plan to
discover/verify/crawl over time.

## What "outside P0/P1/P2" means

Companies outside P0/P1/P2 are **not** automatically "non-tech companies".

They are companies that did not enter the current operational crawl pool under
the current priority rules. There are several reasons:

1. No target SOC/role signal in the LCA data.
2. Target-role evidence exists, but the priority score is too low.
3. The company has target-role evidence but was excluded by an explicit rule,
   such as executive-only small sponsor exclusion.
4. The company may be tech-adjacent or even a tech company, but the available
   LCA filings do not provide enough evidence to prioritize it now.

Important distinction:

```text
No target LCA signal != not a tech company
No target LCA signal = no current evidence in this LCA dataset that it sponsored our target roles
```

## Current inside/outside breakdown

As of 2026-06-28, using `enabled P0/P1/P2` as the crawl-pool definition:

| Pool | Companies | Recent LCA | Has target-role LCA rows | Has salary score | Executive-only excluded |
|---|---:|---:|---:|---:|---:|
| In enabled P0/P1/P2 | 19,114 | 17,955 | 19,114 | 14,831 | 0 |
| Outside enabled P0/P1/P2 | 49,843 | 42,055 | 22,992 | 8,262 | 1,153 |

So the roughly 50k companies outside the crawl pool are not all "no target role"
companies. About 22,992 of them still have some target-role LCA evidence, but
their score or exclusion status keeps them outside the current pool.

## Outside-pool reason buckets

As of 2026-06-28:

| Outside-pool reason | Companies | Recent LCA | LCA >= 5 | Has target-role LCA rows |
|---|---:|---:|---:|---:|
| No target SOC/role signal | 26,684 | 22,373 | 2,566 | 0 |
| Other not in enabled pool | 17,259 | 14,821 | 4,191 | 17,259 |
| Has target signal but score below P2 | 4,747 | 3,972 | 0 | 4,747 |
| Executive-only excluded | 1,153 | 889 | 0 | 986 |

Interpretation:

- **No target SOC/role signal**: no active target SOC match under the current
  `target_soc_roles` definition. These are the lowest-priority group for
  JobPush. They may still include some tech companies, but the LCA data does
  not prove target-role sponsorship.
- **Has target signal but score below P2**: usually one target-role filing with
  insufficient supporting signals such as salary, LCA volume, Chicago, product,
  or LinkedIn signal.
- **Other not in enabled pool**: target evidence exists, but the current
  operational queue has not enabled the company. This bucket should be audited
  when priority thresholds or P2 policy changes.
- **Executive-only excluded**: companies with only 1-2 filings where the filings
  are clearly C-suite/executive-level. These are intentionally removed from the
  crawl pool even if they technically match broad target SOC categories.

## How the P tiers are assigned

Effective tiers come from `jobpush.crawl_targets.priority_tier`.

The score is computed in `jobpush.company_targets_consolidated`, then synced to
`crawl_targets`. Manual overrides can change the effective tier.

Current scoring formula:

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

Current automated tier bands:

| Tier | Rule |
|---|---|
| P1 | `priority_score > 3` |
| P2 | `priority_score IN (3.0, 2.5)` |
| P0 | Manual override only |
| outside pool | no tier, score below tier threshold, disabled, or excluded |

See [`PRIORITY.md`](PRIORITY.md) for component-by-component details.

## SOC role evidence vs raw title evidence

The primary target-role evidence is SOC-based:

- LCA rows contain `soc_code`.
- `jobpush.target_soc_roles` defines which normalized SOC codes are target.
- `target_role_lca_count > 0` means the company has at least one filing whose
  SOC code is currently selected as target.

Raw job titles are used for supplemental signals, such as:

- `product_role_score`
- `product_manager_score`
- title review and classifier training

Therefore, a company can fail to enter the P pool because:

- its SOC codes are outside target SOCs;
- its target SOC rows are too few or weakly supported;
- its raw titles do not add product/PM signals;
- salary or recency signals are weak;
- it was manually downgraded or explicitly excluded.

## Common misreadings to avoid

| Misreading | Correct reading |
|---|---|
| "Outside P pool means not tech." | Outside P pool means not prioritized under current LCA-derived evidence and rules. |
| "No target signal means no target jobs exist at the company." | It only means no target-role sponsorship evidence in this LCA dataset under current SOC mapping. |
| "Recent LCA means good JobPush target." | Recent LCA helps, but the company still needs target-role and score evidence. |
| "Target SOC alone is enough." | Target SOC is necessary for most scores, but P tier depends on total score and exclusions. |
| "P2 companies are bad." | P2 companies are lower frequency/priority, not bad. They remain in the crawl pool. |

## Recommended operating practice

1. Treat P0/P1/P2 as the active crawl product scope.
2. Spend Tavily/search/crawl budget first on P0/P1, then P2.
3. Do not spend budget on outside-pool companies unless:
   - a company is manually promoted;
   - a new priority feature is added;
   - the user specifically wants to audit a segment;
   - refreshed LCA data changes the evidence.
4. Recompute this audit after major changes to:
   - `target_soc_roles`;
   - priority score formula;
   - salary repair;
   - executive-only exclusion;
   - manual override policy;
   - newly loaded LCA disclosure data.

## Reproducible audit SQL

Enabled P pool count:

```sql
SELECT priority_tier, COUNT(*) AS companies
FROM jobpush.crawl_targets
WHERE enabled AND priority_tier IN ('P0','P1','P2')
GROUP BY priority_tier
ORDER BY priority_tier;
```

Inside/outside pool breakdown:

```sql
WITH base AS (
  SELECT
    consolidated.consolidation_key,
    consolidated.lca_count,
    consolidated.recent_lca,
    consolidated.target_role_lca_count,
    consolidated.target_role_score,
    consolidated.salary_score,
    consolidated.priority_score,
    consolidated.executive_only_excluded,
    target.priority_tier,
    COALESCE(target.enabled, FALSE) AS target_enabled
  FROM jobpush.company_targets_consolidated consolidated
  LEFT JOIN jobpush.crawl_targets target USING (consolidation_key)
), bucket AS (
  SELECT
    CASE
      WHEN target_enabled AND priority_tier IN ('P0','P1','P2')
        THEN 'in_enabled_p_pool'
      ELSE 'outside_enabled_p_pool'
    END AS pool,
    *
  FROM base
)
SELECT
  pool,
  COUNT(*) AS companies,
  COUNT(*) FILTER (WHERE recent_lca) AS recent_lca,
  COUNT(*) FILTER (WHERE target_role_lca_count > 0) AS has_target_lca_rows,
  COUNT(*) FILTER (WHERE salary_score > 0) AS has_salary_score,
  COUNT(*) FILTER (WHERE executive_only_excluded) AS executive_only_excluded,
  ROUND(AVG(priority_score)::numeric, 3) AS avg_priority_score
FROM bucket
GROUP BY pool
ORDER BY pool;
```

Outside-pool reason buckets:

```sql
WITH base AS (
  SELECT
    consolidated.*,
    target.priority_tier,
    COALESCE(target.enabled, FALSE) AS target_enabled
  FROM jobpush.company_targets_consolidated consolidated
  LEFT JOIN jobpush.crawl_targets target USING (consolidation_key)
), outside AS (
  SELECT *
  FROM base
  WHERE NOT (target_enabled AND priority_tier IN ('P0','P1','P2'))
)
SELECT
  CASE
    WHEN executive_only_excluded THEN 'executive_only_excluded'
    WHEN COALESCE(target_role_lca_count,0)=0
     AND COALESCE(target_role_score,0)=0 THEN 'no_target_soc_role_signal'
    WHEN COALESCE(priority_score,0) < 2 THEN 'has_target_signal_but_score_below_p2'
    ELSE 'other_not_in_enabled_pool'
  END AS outside_reason,
  COUNT(*) AS companies,
  COUNT(*) FILTER (WHERE recent_lca) AS recent_lca,
  COUNT(*) FILTER (WHERE lca_count >= 5) AS lca_ge_5,
  COUNT(*) FILTER (WHERE target_role_lca_count > 0) AS has_target_lca_rows
FROM outside
GROUP BY 1
ORDER BY companies DESC;
```
