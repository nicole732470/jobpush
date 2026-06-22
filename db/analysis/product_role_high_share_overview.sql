-- Overview of target companies with high in-company product-class LCA share.
-- Uses raw lca_cases.job_title.

\echo '=== High-share cohort sizes (target_role_score > 0) ==='
SELECT
    COUNT(*) FILTER (WHERE product_role_lca_pct = 100) AS companies_at_100_pct,
    COUNT(*) FILTER (WHERE product_role_lca_pct >= 76 AND product_role_lca_pct < 100)
        AS companies_76_to_99_pct,
    COUNT(*) FILTER (WHERE product_role_lca_pct >= 76) AS companies_76_plus_pct
FROM jobpush.company_targets
WHERE target_role_score > 0;

\echo '=== 100% companies: LCA count profile ==='
SELECT
    CASE
        WHEN lca_count = 1 THEN '1 filing'
        WHEN lca_count BETWEEN 2 AND 5 THEN '2-5 filings'
        WHEN lca_count BETWEEN 6 AND 20 THEN '6-20 filings'
        ELSE '21+ filings'
    END AS lca_count_bucket,
    COUNT(*) AS companies,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_100_pct_cohort
FROM jobpush.company_targets
WHERE target_role_score > 0
  AND product_role_lca_pct = 100
GROUP BY 1
ORDER BY MIN(lca_count);

\echo '=== 76%+ companies: single-title vs multi-title (all filings) ==='
WITH high_share AS (
    SELECT fein, lca_count
    FROM jobpush.company_targets
    WHERE target_role_score > 0
      AND product_role_lca_pct >= 76
),
title_stats AS (
    SELECT
        h.fein,
        h.lca_count,
        COUNT(DISTINCT l.job_title) AS distinct_job_titles,
        COUNT(DISTINCT l.job_title)
            FILTER (WHERE jobpush.is_product_role_job_title(l.job_title))
            AS distinct_product_job_titles
    FROM high_share h
    JOIN public.lca_cases l ON l.employer_fein = h.fein
    GROUP BY h.fein, h.lca_count
)
SELECT
    CASE
        WHEN distinct_job_titles = 1 THEN 'single raw job title total'
        WHEN distinct_product_job_titles = 1 THEN 'multiple titles, one product title'
        ELSE 'multiple product titles'
    END AS title_pattern,
    COUNT(*) AS companies,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_76_plus_cohort,
    ROUND(AVG(lca_count), 1) AS avg_lca_count
FROM title_stats
GROUP BY 1
ORDER BY companies DESC;

\echo '=== 100% vs 76-99%: single LCA company share ==='
SELECT
    CASE
        WHEN product_role_lca_pct = 100 THEN '100%'
        ELSE '76-99%'
    END AS share_bucket,
    COUNT(*) AS companies,
    COUNT(*) FILTER (WHERE single_lca_company) AS single_lca_companies,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE single_lca_company) / COUNT(*),
        1
    ) AS pct_single_lca
FROM jobpush.company_targets
WHERE target_role_score > 0
  AND product_role_lca_pct >= 76
GROUP BY 1
ORDER BY 1 DESC;

\echo '=== Top raw job titles among 100% companies ==='
WITH companies_100 AS (
    SELECT fein
    FROM jobpush.company_targets
    WHERE target_role_score > 0
      AND product_role_lca_pct = 100
)
SELECT
    l.job_title,
    jobpush.product_role_job_title_category(l.job_title) AS category,
    COUNT(DISTINCT l.employer_fein) AS companies,
    COUNT(*) AS filings
FROM companies_100 c
JOIN public.lca_cases l ON l.employer_fein = c.fein
GROUP BY l.job_title, 2
ORDER BY companies DESC, filings DESC
LIMIT 20;

\echo '=== Top raw job titles among 76-99% companies ==='
WITH companies_high AS (
    SELECT fein
    FROM jobpush.company_targets
    WHERE target_role_score > 0
      AND product_role_lca_pct >= 76
      AND product_role_lca_pct < 100
)
SELECT
    l.job_title,
    jobpush.product_role_job_title_category(l.job_title) AS category,
    COUNT(DISTINCT l.employer_fein) AS companies,
    COUNT(*) AS filings,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE jobpush.is_product_role_job_title(l.job_title))
            / COUNT(*),
        1
    ) AS pct_product_in_this_title_rows
FROM companies_high c
JOIN public.lca_cases l ON l.employer_fein = c.fein
GROUP BY l.job_title, 2
ORDER BY companies DESC, filings DESC
LIMIT 20;

\echo '=== Product subcategory mix in 76%+ cohort (product filings only) ==='
WITH companies_high AS (
    SELECT fein
    FROM jobpush.company_targets
    WHERE target_role_score > 0
      AND product_role_lca_pct >= 76
)
SELECT
    jobpush.product_role_job_title_category(l.job_title) AS category,
    COUNT(*) AS filings,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_product_filings
FROM companies_high c
JOIN public.lca_cases l ON l.employer_fein = c.fein
WHERE jobpush.is_product_role_job_title(l.job_title)
GROUP BY 1
ORDER BY filings DESC;
