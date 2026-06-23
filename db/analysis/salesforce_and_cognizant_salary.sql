\echo '=== Salesforce consolidated rows ==='
SELECT consolidation_key, canonical_name, member_fein_count, lca_count,
       target_role_lca_count, priority_score, crawl_priority_tier,
       target_role_score, lca_count_score, chicago_score,
       product_role_score, product_manager_score, salary_score,
       linkedin_top_employer_score, linkedin_employer_key
FROM jobpush.company_targets_consolidated
WHERE canonical_name ILIKE '%salesforce%'
   OR consolidation_key ILIKE '%salesforce%'
ORDER BY lca_count DESC
LIMIT 15;

\echo '=== Cognizant US Corp: salary distribution (target roles, valid annualized) ==='
WITH fein AS (
    SELECT fein FROM public.companies
    WHERE name ILIKE 'COGNIZANT TECHNOLOGY SOLUTIONS US CORP%'
    LIMIT 1
),
salaries AS (
    SELECT
        jobpush.lca_annual_salary(lcase.wage_rate_of_pay_from, lcase.wage_unit_of_pay) AS annual_salary
    FROM public.lca_cases lcase
    JOIN fein f ON f.fein = lcase.employer_fein
    JOIN jobpush.target_soc_roles target
      ON target.active
     AND target.normalized_soc_code = jobpush.normalize_soc_code(lcase.soc_code)
    WHERE jobpush.lca_annual_salary(lcase.wage_rate_of_pay_from, lcase.wage_unit_of_pay) IS NOT NULL
)
SELECT
    COUNT(*) AS n,
    MIN(annual_salary)::numeric(12,0) AS min_salary,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY annual_salary)::numeric(12,0) AS p25,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY annual_salary)::numeric(12,0) AS median,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY annual_salary)::numeric(12,0) AS p75,
    MAX(annual_salary)::numeric(12,0) AS max_salary,
    COUNT(*) FILTER (WHERE annual_salary < 90000) AS under_90k,
    COUNT(*) FILTER (WHERE annual_salary >= 90000) AS at_or_above_90k
FROM salaries;

\echo '=== Cognizant US Corp: under-90k target filings by job_title (top 15) ==='
WITH fein AS (
    SELECT fein FROM public.companies
    WHERE name ILIKE 'COGNIZANT TECHNOLOGY SOLUTIONS US CORP%'
    LIMIT 1
)
SELECT
    lcase.job_title,
    lcase.soc_code,
    lcase.wage_rate_of_pay_from,
    lcase.wage_unit_of_pay,
    jobpush.lca_annual_salary(lcase.wage_rate_of_pay_from, lcase.wage_unit_of_pay)::numeric(12,0) AS annual_salary,
    COUNT(*) AS filing_count
FROM public.lca_cases lcase
JOIN fein f ON f.fein = lcase.employer_fein
JOIN jobpush.target_soc_roles target
  ON target.active
 AND target.normalized_soc_code = jobpush.normalize_soc_code(lcase.soc_code)
WHERE jobpush.lca_annual_salary(lcase.wage_rate_of_pay_from, lcase.wage_unit_of_pay) < 90000
GROUP BY 1, 2, 3, 4, 5
ORDER BY filing_count DESC
LIMIT 15;

\echo '=== Cognizant US Corp: JC60 title sample (raw wage fields) ==='
WITH fein AS (
    SELECT fein FROM public.companies
    WHERE name ILIKE 'COGNIZANT TECHNOLOGY SOLUTIONS US CORP%'
    LIMIT 1
)
SELECT
    lcase.job_title,
    lcase.wage_rate_of_pay_from,
    lcase.wage_rate_of_pay_to,
    lcase.wage_unit_of_pay,
    lcase.prevailing_wage,
    lcase.pw_unit_of_pay,
    lcase.received_date,
    lcase.worksite_city,
    lcase.worksite_state
FROM public.lca_cases lcase
JOIN fein f ON f.fein = lcase.employer_fein
WHERE lcase.job_title ILIKE '%JC60%'
ORDER BY lcase.received_date DESC
LIMIT 8;

\echo '=== Cognizant US Corp: wage_unit breakdown (target roles) ==='
WITH fein AS (
    SELECT fein FROM public.companies
    WHERE name ILIKE 'COGNIZANT TECHNOLOGY SOLUTIONS US CORP%'
    LIMIT 1
)
SELECT
    lcase.wage_unit_of_pay,
    COUNT(*) AS filings,
    MIN(lcase.wage_rate_of_pay_from)::numeric(12,2) AS min_wage_from,
    MAX(lcase.wage_rate_of_pay_from)::numeric(12,2) AS max_wage_from,
    MIN(jobpush.lca_annual_salary(lcase.wage_rate_of_pay_from, lcase.wage_unit_of_pay))::numeric(12,0) AS min_annualized,
    PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY jobpush.lca_annual_salary(lcase.wage_rate_of_pay_from, lcase.wage_unit_of_pay)
    )::numeric(12,0) AS median_annualized
FROM public.lca_cases lcase
JOIN fein f ON f.fein = lcase.employer_fein
JOIN jobpush.target_soc_roles target
  ON target.active
 AND target.normalized_soc_code = jobpush.normalize_soc_code(lcase.soc_code)
WHERE jobpush.lca_annual_salary(lcase.wage_rate_of_pay_from, lcase.wage_unit_of_pay) IS NOT NULL
GROUP BY 1
ORDER BY filings DESC;
