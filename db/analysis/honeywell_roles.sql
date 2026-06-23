\echo '=== Honeywell consolidated rows ==='
SELECT consolidation_key, canonical_name, lca_count, target_role_lca_count,
       priority_score, crawl_priority_tier,
       target_role_score, product_role_score, salary_score, linkedin_top_employer_score
FROM jobpush.company_targets_consolidated
WHERE canonical_name ILIKE '%honeywell%'
ORDER BY lca_count DESC
LIMIT 10;

\echo '=== Honeywell target SOC summary ==='
WITH honeywell_feins AS (
    SELECT unnest(member_feins) AS fein
    FROM jobpush.company_targets_consolidated
    WHERE canonical_name ILIKE '%honeywell%'
    UNION
    SELECT fein FROM public.companies WHERE name ILIKE '%honeywell%'
)
SELECT
    target.representative_title AS soc_title,
    target.normalized_soc_code,
    COUNT(*) AS filing_count
FROM public.lca_cases lcase
JOIN honeywell_feins hf ON hf.fein = lcase.employer_fein
JOIN jobpush.target_soc_roles target
  ON target.active
 AND target.normalized_soc_code = jobpush.normalize_soc_code(lcase.soc_code)
GROUP BY 1, 2
ORDER BY filing_count DESC;

\echo '=== Honeywell target-role job_title (top by count) ==='
WITH honeywell_feins AS (
    SELECT unnest(member_feins) AS fein
    FROM jobpush.company_targets_consolidated
    WHERE canonical_name ILIKE '%honeywell%'
    UNION
    SELECT fein FROM public.companies WHERE name ILIKE '%honeywell%'
)
SELECT
    lcase.job_title,
    target.representative_title AS soc_title,
    jobpush.is_product_role_job_title(lcase.job_title) AS is_product_role,
    jobpush.is_product_manager_job_title(lcase.job_title) AS is_product_manager,
    COUNT(*) AS filing_count,
    MIN(jobpush.lca_annual_salary(lcase.wage_rate_of_pay_from, lcase.wage_unit_of_pay))::numeric(12,0)
        AS min_annual_salary
FROM public.lca_cases lcase
JOIN honeywell_feins hf ON hf.fein = lcase.employer_fein
JOIN jobpush.target_soc_roles target
  ON target.active
 AND target.normalized_soc_code = jobpush.normalize_soc_code(lcase.soc_code)
GROUP BY 1, 2, 3, 4
ORDER BY filing_count DESC
LIMIT 35;
