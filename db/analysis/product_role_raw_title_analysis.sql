-- Target-role companies only (target_role_score > 0).
-- Uses raw lca_cases.job_title, not soc_title or normalized mapping titles.

\echo '=== Overall product-class share (raw job_title) ==='
WITH target_cos AS (
    SELECT fein FROM jobpush.company_targets WHERE target_role_score > 0
),
filings AS (
    SELECT
        c.fein,
        l.job_title,
        jobpush.is_product_role_title(l.job_title) AS is_product_role
    FROM target_cos c
    JOIN public.lca_cases l ON l.employer_fein = c.fein
),
company_stats AS (
    SELECT
        fein,
        COUNT(*) AS total_filings,
        COUNT(*) FILTER (WHERE is_product_role) AS product_filings
    FROM filings
    GROUP BY fein
)
SELECT
    COUNT(*) AS target_companies,
    SUM(total_filings) AS total_lca_filings,
    SUM(product_filings) AS product_role_filings,
    ROUND(100.0 * SUM(product_filings) / NULLIF(SUM(total_filings), 0), 2)
        AS product_share_of_all_lca_pct,
    COUNT(*) FILTER (WHERE product_filings > 0) AS companies_with_product_role,
    ROUND(100.0 * COUNT(*) FILTER (WHERE product_filings > 0) / COUNT(*), 1)
        AS pct_companies_with_product_role
FROM company_stats;

\echo '=== Per-company product share buckets (raw job_title) ==='
WITH target_cos AS (
    SELECT fein FROM jobpush.company_targets WHERE target_role_score > 0
),
filings AS (
    SELECT
        c.fein,
        jobpush.is_product_role_title(l.job_title) AS is_product_role
    FROM target_cos c
    JOIN public.lca_cases l ON l.employer_fein = c.fein
),
company_stats AS (
    SELECT
        fein,
        ROUND(100.0 * COUNT(*) FILTER (WHERE is_product_role)
            / NULLIF(COUNT(*), 0), 1) AS product_pct
    FROM filings
    GROUP BY fein
)
SELECT
    CASE
        WHEN product_pct = 0 THEN '0%'
        WHEN product_pct <= 10 THEN '1-10%'
        WHEN product_pct <= 25 THEN '11-25%'
        WHEN product_pct <= 50 THEN '26-50%'
        WHEN product_pct <= 75 THEN '51-75%'
        ELSE '76-100%'
    END AS product_share_bucket,
    COUNT(*) AS companies,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_target_companies
FROM company_stats
GROUP BY 1
ORDER BY MIN(product_pct);

\echo '=== Top product-class raw job titles ==='
WITH target_cos AS (
    SELECT fein FROM jobpush.company_targets WHERE target_role_score > 0
)
SELECT l.job_title, COUNT(*) AS filings
FROM target_cos c
JOIN public.lca_cases l ON l.employer_fein = c.fein
WHERE jobpush.is_product_role_title(l.job_title)
GROUP BY l.job_title
ORDER BY filings DESC
LIMIT 30;
