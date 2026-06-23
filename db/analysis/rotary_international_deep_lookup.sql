\echo '=== All LCA filings with rotary in employer name ==='
SELECT employer_fein, employer_name, employer_city, employer_state,
       count(*) AS filings,
       count(*) FILTER (WHERE job_title IS NOT NULL) AS with_title
FROM public.lca_cases
WHERE employer_name ILIKE '%rotary%'
GROUP BY 1, 2, 3, 4
ORDER BY filings DESC;

\echo '=== Rotary Corporation filing detail ==='
SELECT case_number, employer_name, employer_city, employer_state,
       job_title, soc_code, case_status, received_date, worksite_city, worksite_state
FROM public.lca_cases
WHERE employer_fein = '58-0959394'
ORDER BY received_date DESC
LIMIT 10;

\echo '=== international / foundation variants ==='
SELECT employer_fein, employer_name, employer_city, employer_state, count(*) AS filings
FROM public.lca_cases
WHERE employer_name ILIKE '%rotary%international%'
   OR employer_name ILIKE '%rotary foundation%'
   OR employer_name ILIKE '%rotary club%'
   OR employer_name ILIKE '%the rotary%'
GROUP BY 1, 2, 3, 4
ORDER BY filings DESC
LIMIT 25;

\echo '=== company_targets singleton ==='
SELECT * FROM jobpush.company_targets_consolidated
WHERE consolidation_key = '58-0959394';
