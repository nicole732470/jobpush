-- Score component breakdown for priority_score 2.0 and 3.0 (consolidated).

\echo '=== priority 2.0: component pattern counts ==='
SELECT
    target_role_score::text AS target,
    lca_count_score::text AS lca_cnt,
    chicago_score::text AS chicago,
    product_role_score::text AS product,
    product_manager_score::text AS pm,
    salary_score::text AS salary,
    linkedin_top_employer_score::text AS linkedin,
    COUNT(*) AS companies
FROM jobpush.company_targets_consolidated
WHERE priority_score = 2.0
GROUP BY 1, 2, 3, 4, 5, 6, 7
ORDER BY companies DESC
LIMIT 15;

\echo '=== priority 3.0: component pattern counts ==='
SELECT
    target_role_score::text AS target,
    lca_count_score::text AS lca_cnt,
    chicago_score::text AS chicago,
    product_role_score::text AS product,
    product_manager_score::text AS pm,
    salary_score::text AS salary,
    linkedin_top_employer_score::text AS linkedin,
    COUNT(*) AS companies
FROM jobpush.company_targets_consolidated
WHERE priority_score = 3.0
GROUP BY 1, 2, 3, 4, 5, 6, 7
ORDER BY companies DESC
LIMIT 15;

\echo '=== priority 2.0: which single component tips the score (among target=1) ==='
SELECT
    CASE
        WHEN lca_count_score = 1 AND product_role_score = 0 AND salary_score = 0
            THEN 'target + lca_count only (2.0)'
        WHEN lca_count_score = 0 AND product_role_score = 1 AND salary_score = 0
            THEN 'target + product_role only (2.0)'
        WHEN lca_count_score = 0 AND product_role_score = 0 AND salary_score = 1
            THEN 'target + salary only (2.0)'
        WHEN lca_count_score = 1 AND product_role_score = 1
            THEN 'target + lca + product (3.0 pattern on 2?)'
        WHEN chicago_score = 0.5
            THEN 'includes chicago 0.5'
        WHEN product_manager_score = 0.25
            THEN 'includes pm 0.25'
        ELSE 'other mix'
    END AS pattern,
    COUNT(*) AS companies
FROM jobpush.company_targets_consolidated
WHERE priority_score = 2.0
  AND target_role_score = 1
GROUP BY 1
ORDER BY companies DESC;

\echo '=== priority 3.0: which components add the third point ==='
SELECT
    CASE
        WHEN lca_count_score = 1 AND product_role_score = 1 AND salary_score = 0 AND chicago_score = 0 AND product_manager_score = 0
            THEN 'target + lca + product (3.0)'
        WHEN lca_count_score = 1 AND product_role_score = 0 AND salary_score = 1 AND chicago_score = 0 AND product_manager_score = 0
            THEN 'target + lca + salary (3.0)'
        WHEN lca_count_score = 1 AND chicago_score = 0.5 AND product_role_score = 0 AND salary_score = 0
            THEN 'target + lca + chicago (2.5 not 3)'
        WHEN lca_count_score = 1 AND product_role_score = 0 AND salary_score = 0 AND product_manager_score = 0.25
            THEN 'target + lca + pm (3.25 not 3)'
        WHEN lca_count_score = 0 AND product_role_score = 1 AND salary_score = 1
            THEN 'target + product + salary (3.0)'
        WHEN lca_count_score = 1 AND product_role_score = 1 AND salary_score = 1
            THEN 'target + lca + product + salary (4.0 not 3)'
        WHEN linkedin_top_employer_score = 1
            THEN 'includes linkedin +1'
        ELSE 'other 3.0 mix'
    END AS pattern,
    COUNT(*) AS companies
FROM jobpush.company_targets_consolidated
WHERE priority_score = 3.0
  AND target_role_score = 1
GROUP BY 1
ORDER BY companies DESC;

\echo '=== priority 2.0 samples (top lca_count) ==='
SELECT canonical_name, lca_count, target_role_lca_count,
       target_role_score, lca_count_score, chicago_score,
       product_role_score, product_manager_score, salary_score,
       linkedin_top_employer_score, priority_score
FROM jobpush.company_targets_consolidated
WHERE priority_score = 2.0
ORDER BY lca_count DESC
LIMIT 8;

\echo '=== priority 3.0 samples (top lca_count) ==='
SELECT canonical_name, lca_count, target_role_lca_count,
       target_role_score, lca_count_score, chicago_score,
       product_role_score, product_manager_score, salary_score,
       linkedin_top_employer_score, priority_score
FROM jobpush.company_targets_consolidated
WHERE priority_score = 3.0
ORDER BY lca_count DESC
LIMIT 8;

\echo '=== totals ==='
SELECT priority_score, COUNT(*) AS companies
FROM jobpush.company_targets_consolidated
WHERE priority_score IN (2.0, 3.0)
GROUP BY priority_score;
