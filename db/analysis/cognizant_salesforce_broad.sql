\echo '=== Cognizant US Corp: CRM/SFDC related job titles ==='
WITH fein AS (
    SELECT fein FROM public.companies
    WHERE name ILIKE 'COGNIZANT TECHNOLOGY SOLUTIONS US CORP%'
    LIMIT 1
)
SELECT lcase.job_title, lcase.soc_code, COUNT(*) AS n
FROM public.lca_cases lcase
JOIN fein f ON f.fein = lcase.employer_fein
WHERE lcase.job_title ~* '(salesforce|sfdc|force\.com|crm developer|crm architect|crm consultant)'
GROUP BY 1, 2
ORDER BY n DESC
LIMIT 20;

\echo '=== Cognizant US Corp: min target-role salary (why salary_score=0) ==='
WITH fein AS (
    SELECT fein FROM public.companies
    WHERE name ILIKE 'COGNIZANT TECHNOLOGY SOLUTIONS US CORP%'
    LIMIT 1
)
SELECT
    lcase.job_title,
    lcase.soc_code,
    jobpush.lca_annual_salary(lcase.wage_rate_of_pay_from, lcase.wage_unit_of_pay)::numeric(12,0) AS annual_salary,
    lcase.received_date
FROM public.lca_cases lcase
JOIN fein f ON f.fein = lcase.employer_fein
JOIN jobpush.target_soc_roles target
  ON target.active
 AND target.normalized_soc_code = jobpush.normalize_soc_code(lcase.soc_code)
WHERE jobpush.lca_annual_salary(lcase.wage_rate_of_pay_from, lcase.wage_unit_of_pay) IS NOT NULL
ORDER BY annual_salary ASC NULLS LAST
LIMIT 5;
