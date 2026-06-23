\echo '=== 2.25: salary evidence summary ==='
SELECT
    COUNT(*) AS companies,
    COUNT(*) FILTER (WHERE target_role_valid_salary_lca_count = 0) AS no_valid_salary_rows,
    COUNT(*) FILTER (WHERE target_role_valid_salary_lca_count > 0
                       AND target_role_min_annual_salary < 90000) AS has_salary_but_under_90k,
    COUNT(*) FILTER (WHERE target_role_min_annual_salary >= 90000) AS min_salary_at_least_90k,
    ROUND(AVG(target_role_min_annual_salary) FILTER (
        WHERE target_role_valid_salary_lca_count > 0
    ), 0) AS avg_min_salary_when_present,
    ROUND(MIN(target_role_min_annual_salary) FILTER (
        WHERE target_role_valid_salary_lca_count > 0
    ), 0) AS min_of_mins,
    ROUND(MAX(target_role_min_annual_salary) FILTER (
        WHERE target_role_valid_salary_lca_count > 0
    ), 0) AS max_of_mins
FROM jobpush.company_targets_consolidated
WHERE priority_score = 2.25;

\echo '=== 2.25: full detail ==='
SELECT
    canonical_name,
    lca_count,
    target_role_lca_count,
    target_role_valid_salary_lca_count,
    target_role_invalid_salary_lca_count,
    target_role_min_annual_salary,
    salary_score,
    product_role_score,
    product_manager_score,
    priority_score
FROM jobpush.company_targets_consolidated
WHERE priority_score = 2.25
ORDER BY target_role_min_annual_salary DESC NULLS LAST, lca_count DESC;
