\echo '=== Cognizant: exactly 60000 filings ==='
WITH fein AS (
    SELECT fein FROM public.companies
    WHERE name ILIKE 'COGNIZANT TECHNOLOGY SOLUTIONS US CORP%'
    LIMIT 1
)
SELECT COUNT(*) AS filings_at_60k,
       MIN(lcase.received_date) AS earliest,
       MAX(lcase.received_date) AS latest
FROM public.lca_cases lcase
JOIN fein f ON f.fein = lcase.employer_fein
JOIN jobpush.target_soc_roles target
  ON target.active
 AND target.normalized_soc_code = jobpush.normalize_soc_code(lcase.soc_code)
WHERE jobpush.lca_annual_salary(lcase.wage_rate_of_pay_from, lcase.wage_unit_of_pay) = 60000;

\echo '=== Salesforce: min target salary (why salary_score=0) ==='
WITH sf_feins AS (
    SELECT unnest(member_feins) AS fein
    FROM jobpush.company_targets_consolidated
    WHERE consolidation_key = 'salesforce'
)
SELECT lcase.job_title, lcase.soc_code,
       jobpush.lca_annual_salary(lcase.wage_rate_of_pay_from, lcase.wage_unit_of_pay)::numeric(12,0) AS annual_salary,
       lcase.received_date
FROM public.lca_cases lcase
JOIN sf_feins sf ON sf.fein = lcase.employer_fein
JOIN jobpush.target_soc_roles target
  ON target.active
 AND target.normalized_soc_code = jobpush.normalize_soc_code(lcase.soc_code)
WHERE jobpush.lca_annual_salary(lcase.wage_rate_of_pay_from, lcase.wage_unit_of_pay) IS NOT NULL
ORDER BY annual_salary ASC
LIMIT 5;
