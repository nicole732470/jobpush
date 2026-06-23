\echo '=== All Analyst-related LCA titles ==='
SELECT job_title, soc_code, worksite_city, worksite_state,
       received_date, case_status
FROM public.lca_cases
WHERE employer_fein IN ('36-4486492', '88-3028720')
  AND job_title ILIKE '%analyst%'
ORDER BY received_date DESC;

\echo '=== Analyst title rollup with salary ==='
SELECT job_title, soc_code, count(*) AS filings,
       min(received_date) AS first_seen, max(received_date) AS last_seen,
       min(jobpush.lca_annual_salary(wage_rate_of_pay_from, wage_unit_of_pay))::numeric(12,0) AS min_annual,
       max(jobpush.lca_annual_salary(wage_rate_of_pay_from, wage_unit_of_pay))::numeric(12,0) AS max_annual
FROM public.lca_cases
WHERE employer_fein IN ('36-4486492', '88-3028720')
  AND job_title ILIKE '%analyst%'
GROUP BY 1, 2
ORDER BY filings DESC, job_title;

\echo '=== Analyst worksite locations ==='
SELECT worksite_city, worksite_state, count(*) AS filings
FROM public.lca_cases
WHERE employer_fein IN ('36-4486492', '88-3028720')
  AND job_title ILIKE '%analyst%'
GROUP BY 1, 2
ORDER BY filings DESC;

\echo '=== Related: Associate titles (often paired with Analyst) ==='
SELECT job_title, soc_code, count(*) AS filings
FROM public.lca_cases
WHERE employer_fein IN ('36-4486492', '88-3028720')
  AND (job_title ILIKE '%associate%' AND job_title NOT ILIKE '%analyst%')
GROUP BY 1, 2
ORDER BY filings DESC;
