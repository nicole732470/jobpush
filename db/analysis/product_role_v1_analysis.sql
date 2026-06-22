-- Product-class role analysis for target-role companies only.
-- Uses raw lca_cases.job_title.

\echo '=== Overall product-class share ==='
WITH target_cos AS (
    SELECT fein FROM jobpush.company_targets WHERE target_role_score > 0
),
filings AS (
    SELECT
        c.fein,
        l.job_title,
        jobpush.is_product_role_job_title(l.job_title) AS is_product_role
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
    SUM(product_filings) AS product_class_filings,
    ROUND(100.0 * SUM(product_filings) / NULLIF(SUM(total_filings), 0), 2)
        AS product_share_of_all_lca_pct,
    COUNT(*) FILTER (WHERE product_filings > 0) AS companies_with_product_class,
    ROUND(100.0 * COUNT(*) FILTER (WHERE product_filings > 0) / COUNT(*), 1)
        AS pct_companies_with_product_class
FROM company_stats;

\echo '=== Product-class subcategory share (all target-company LCA) ==='
WITH target_cos AS (
    SELECT fein FROM jobpush.company_targets WHERE target_role_score > 0
),
classified AS (
    SELECT jobpush.product_role_job_title_category(l.job_title) AS category
    FROM target_cos c
    JOIN public.lca_cases l ON l.employer_fein = c.fein
    WHERE jobpush.is_product_role_job_title(l.job_title)
)
SELECT
    category,
    COUNT(*) AS filings,
    ROUND(
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER (),
        2
    ) AS pct_of_product_class_filings
FROM classified
GROUP BY category
ORDER BY filings DESC;

\echo '=== Per-company product-class share buckets ==='
WITH target_cos AS (
    SELECT fein FROM jobpush.company_targets WHERE target_role_score > 0
),
filings AS (
    SELECT
        c.fein,
        jobpush.is_product_role_job_title(l.job_title) AS is_product_role
    FROM target_cos c
    JOIN public.lca_cases l ON l.employer_fein = c.fein
),
company_stats AS (
    SELECT
        fein,
        ROUND(
            100.0 * COUNT(*) FILTER (WHERE is_product_role) / NULLIF(COUNT(*), 0),
            1
        ) AS product_pct
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

\echo '=== Top raw job titles in each product subcategory ==='
WITH target_cos AS (
    SELECT fein FROM jobpush.company_targets WHERE target_role_score > 0
),
classified AS (
    SELECT
        jobpush.product_role_job_title_category(l.job_title) AS category,
        l.job_title
    FROM target_cos c
    JOIN public.lca_cases l ON l.employer_fein = c.fein
    WHERE jobpush.is_product_role_job_title(l.job_title)
),
ranked AS (
    SELECT
        category,
        job_title,
        COUNT(*) AS filings,
        ROW_NUMBER() OVER (
            PARTITION BY category
            ORDER BY COUNT(*) DESC, job_title
        ) AS rn
    FROM classified
    GROUP BY category, job_title
)
SELECT category, job_title, filings
FROM ranked
WHERE rn <= 5
ORDER BY category, filings DESC;
