-- Priority distribution and LinkedIn score audit (read-only).

\echo '=== priority_score distribution (consolidated) ==='
SELECT priority_score, COUNT(*) AS companies
FROM jobpush.company_targets_consolidated
GROUP BY priority_score
ORDER BY priority_score DESC;

\echo '=== component score sums (target_role=1 only) ==='
SELECT
    COUNT(*) FILTER (WHERE target_role_score = 1) AS target_companies,
    COUNT(*) FILTER (WHERE target_role_score = 1 AND lca_count_score = 1) AS with_lca_count,
    COUNT(*) FILTER (WHERE target_role_score = 1 AND chicago_score = 0.5) AS with_chicago,
    COUNT(*) FILTER (WHERE target_role_score = 1 AND product_role_score = 1) AS with_product_role,
    COUNT(*) FILTER (WHERE target_role_score = 1 AND product_manager_score = 0.25) AS with_pm,
    COUNT(*) FILTER (WHERE target_role_score = 1 AND salary_score = 1) AS with_salary,
    COUNT(*) FILTER (WHERE target_role_score = 1 AND linkedin_top_employer_score = 1) AS with_linkedin
FROM jobpush.company_targets_consolidated;

\echo '=== linkedin score=1 but linkedin_employer_key IS NULL ==='
SELECT COUNT(*) AS cnt
FROM jobpush.company_targets_consolidated
WHERE linkedin_top_employer_score = 1
  AND linkedin_employer_key IS NULL;

\echo '=== sample: linkedin=1, key null, top by lca_count ==='
SELECT canonical_name, consolidation_key, is_merged_group,
       member_feins, primary_fein, lca_count, target_role_lca_count,
       priority_score, linkedin_employer_key, linkedin_top_employer_score
FROM jobpush.company_targets_consolidated
WHERE linkedin_top_employer_score = 1
  AND linkedin_employer_key IS NULL
ORDER BY lca_count DESC
LIMIT 20;

\echo '=== Abstract Security row ==='
SELECT *
FROM jobpush.company_targets_consolidated
WHERE canonical_name ILIKE '%abstract%security%'
   OR canonical_name ILIKE '%abstract%'
ORDER BY lca_count DESC
LIMIT 15;

\echo '=== LinkedIn matches for Abstract-related FEINs ==='
SELECT m.fein, c.name, m.employer_key, m.match_source, m.match_key, m.linkedin_name
FROM jobpush.linkedin_top_employer_company_matches m
JOIN public.companies c ON c.fein = m.fein
WHERE m.employer_key = 'abstract'
   OR c.name ILIKE '%abstract%'
ORDER BY c.lca_count DESC
LIMIT 25;

\echo '=== match terms for abstract employer_key ==='
SELECT * FROM jobpush.linkedin_top_employer_match_terms
WHERE employer_key = 'abstract';

\echo '=== priority_score histogram buckets ==='
SELECT
    CASE
        WHEN priority_score = 0 THEN '0'
        WHEN priority_score <= 1 THEN '0-1'
        WHEN priority_score <= 2 THEN '1-2'
        WHEN priority_score <= 3 THEN '2-3'
        WHEN priority_score <= 4 THEN '3-4'
        WHEN priority_score <= 5 THEN '4-5'
        ELSE '5+'
    END AS bucket,
    COUNT(*) AS companies
FROM jobpush.company_targets_consolidated
GROUP BY 1
ORDER BY MIN(priority_score);
