\echo '=== priority 2.5: component patterns ==='
SELECT
    target_role_score::text AS target,
    lca_count_score::text AS lca,
    chicago_score::text AS chicago,
    product_role_score::text AS product,
    product_manager_score::text AS pm,
    salary_score::text AS salary,
    linkedin_top_employer_score::text AS linkedin,
    COUNT(*) AS companies
FROM jobpush.company_targets_consolidated
WHERE priority_score = 2.5
GROUP BY 1,2,3,4,5,6,7
ORDER BY companies DESC;

\echo '=== priority 2.25: component patterns ==='
SELECT
    target_role_score::text AS target,
    lca_count_score::text AS lca,
    chicago_score::text AS chicago,
    product_role_score::text AS product,
    product_manager_score::text AS pm,
    salary_score::text AS salary,
    linkedin_top_employer_score::text AS linkedin,
    COUNT(*) AS companies
FROM jobpush.company_targets_consolidated
WHERE priority_score = 2.25
GROUP BY 1,2,3,4,5,6,7
ORDER BY companies DESC;

\echo '=== 2.5 samples ==='
SELECT canonical_name, employer_city, employer_state, lca_count,
       lca_count_score, chicago_score, salary_score, product_role_score,
       product_manager_score, linkedin_top_employer_score, priority_score
FROM jobpush.company_targets_consolidated
WHERE priority_score = 2.5
ORDER BY lca_count DESC LIMIT 6;

\echo '=== 2.25 samples ==='
SELECT canonical_name, employer_city, employer_state, lca_count,
       lca_count_score, chicago_score, salary_score, product_role_score,
       product_manager_score, linkedin_top_employer_score, priority_score
FROM jobpush.company_targets_consolidated
WHERE priority_score = 2.25
ORDER BY lca_count DESC LIMIT 6;

\echo '=== totals ==='
SELECT priority_score, COUNT(*) FROM jobpush.company_targets_consolidated
WHERE priority_score IN (2.25, 2.5) GROUP BY 1;
