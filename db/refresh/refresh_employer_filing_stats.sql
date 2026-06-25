-- Rebuild FEIN-level LCA aggregates in one pass over public.lca_cases.
-- JobPush read-only on shared data; results stored in jobpush.employer_filing_stats.

BEGIN;

TRUNCATE jobpush.employer_filing_stats;

WITH dataset_window AS (
    SELECT MAX(decision_date) AS max_decision_date
    FROM public.lca_cases
), lca_enriched AS (
    SELECT
        lcase.employer_fein AS fein,
        lcase.decision_date,
        jobpush.is_executive_level_job_title(lcase.job_title) AS is_executive_level,
        target.normalized_soc_code,
        jobpush.lca_annual_salary(
            lcase.wage_rate_of_pay_from,
            lcase.wage_unit_of_pay
        ) AS target_role_annual_salary,
        jobpush.is_product_role_job_title(lcase.job_title) AS is_product_role,
        jobpush.is_product_manager_job_title(lcase.job_title) AS is_product_manager
    FROM public.lca_cases lcase
    LEFT JOIN jobpush.target_soc_roles target
        ON target.active
       AND target.normalized_soc_code = jobpush.normalize_soc_code(lcase.soc_code)
    WHERE lcase.employer_fein IS NOT NULL
)
INSERT INTO jobpush.employer_filing_stats (
    fein,
    lca_case_count,
    executive_level_lca_count,
    target_role_lca_count,
    target_role_min_annual_salary,
    target_role_valid_salary_lca_count,
    target_role_invalid_salary_lca_count,
    has_product_role_job,
    has_product_manager_job,
    product_role_lca_count,
    last_decision_date,
    dataset_max_decision_date,
    refreshed_at
)
SELECT
    enriched.fein,
    COUNT(*)::INTEGER AS lca_case_count,
    COUNT(*) FILTER (WHERE enriched.is_executive_level)::INTEGER
        AS executive_level_lca_count,
    COUNT(enriched.normalized_soc_code)::INTEGER AS target_role_lca_count,
    MIN(enriched.target_role_annual_salary) FILTER (
        WHERE enriched.normalized_soc_code IS NOT NULL
          AND enriched.target_role_annual_salary IS NOT NULL
    )::NUMERIC(14, 2) AS target_role_min_annual_salary,
    COUNT(*) FILTER (
        WHERE enriched.normalized_soc_code IS NOT NULL
          AND enriched.target_role_annual_salary IS NOT NULL
    )::INTEGER AS target_role_valid_salary_lca_count,
    COUNT(*) FILTER (
        WHERE enriched.normalized_soc_code IS NOT NULL
          AND enriched.target_role_annual_salary IS NULL
    )::INTEGER AS target_role_invalid_salary_lca_count,
    COALESCE(BOOL_OR(enriched.is_product_role), FALSE) AS has_product_role_job,
    COALESCE(BOOL_OR(enriched.is_product_manager), FALSE) AS has_product_manager_job,
    COUNT(*) FILTER (WHERE enriched.is_product_role)::INTEGER AS product_role_lca_count,
    MAX(enriched.decision_date) AS last_decision_date,
    window_row.max_decision_date AS dataset_max_decision_date,
    now() AS refreshed_at
FROM lca_enriched enriched
CROSS JOIN dataset_window window_row
GROUP BY enriched.fein, window_row.max_decision_date;

COMMIT;
