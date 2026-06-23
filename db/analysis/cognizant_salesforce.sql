\echo '=== Cognizant consolidated rows ==='
SELECT consolidation_key, canonical_name, member_fein_count, lca_count,
       target_role_lca_count, priority_score, crawl_priority_tier,
       target_role_score, lca_count_score, chicago_score,
       product_role_score, product_manager_score, salary_score,
       linkedin_top_employer_score, linkedin_employer_key
FROM jobpush.company_targets_consolidated
WHERE canonical_name ILIKE '%cognizant%'
ORDER BY lca_count DESC
LIMIT 10;

\echo '=== Cognizant Salesforce filings (job_title ILIKE salesforce) ==='
WITH cognizant_feins AS (
    SELECT unnest(member_feins) AS fein
    FROM jobpush.company_targets_consolidated
    WHERE canonical_name ILIKE '%cognizant%'
    UNION
    SELECT fein FROM public.companies
    WHERE name ILIKE '%cognizant%'
)
SELECT
    lcase.job_title,
    lcase.soc_code,
    target.representative_title AS target_soc_title,
    (target.normalized_soc_code IS NOT NULL) AS is_target_role,
    jobpush.is_product_role_job_title(lcase.job_title) AS is_product_role,
    jobpush.is_product_manager_job_title(lcase.job_title) AS is_product_manager,
    COUNT(*) AS filing_count,
    MIN(jobpush.lca_annual_salary(lcase.wage_rate_of_pay_from, lcase.wage_unit_of_pay))::numeric(12,0) AS min_salary,
    MAX(jobpush.lca_annual_salary(lcase.wage_rate_of_pay_from, lcase.wage_unit_of_pay))::numeric(12,0) AS max_salary
FROM public.lca_cases lcase
JOIN cognizant_feins cf ON cf.fein = lcase.employer_fein
LEFT JOIN jobpush.target_soc_roles target
  ON target.active
 AND target.normalized_soc_code = jobpush.normalize_soc_code(lcase.soc_code)
WHERE lcase.job_title ILIKE '%salesforce%'
GROUP BY 1, 2, 3, 4, 5, 6
ORDER BY filing_count DESC;

\echo '=== Cognizant Salesforce summary ==='
WITH cognizant_feins AS (
    SELECT unnest(member_feins) AS fein
    FROM jobpush.company_targets_consolidated
    WHERE canonical_name ILIKE '%cognizant%'
    UNION
    SELECT fein FROM public.companies
    WHERE name ILIKE '%cognizant%'
)
SELECT
    COUNT(*) AS total_salesforce_filings,
    COUNT(*) FILTER (
        WHERE EXISTS (
            SELECT 1 FROM jobpush.target_soc_roles t
            WHERE t.active
              AND t.normalized_soc_code = jobpush.normalize_soc_code(lcase.soc_code)
        )
    ) AS target_role_salesforce_filings
FROM public.lca_cases lcase
JOIN cognizant_feins cf ON cf.fein = lcase.employer_fein
WHERE lcase.job_title ILIKE '%salesforce%';
