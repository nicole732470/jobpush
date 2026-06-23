\echo '=== Raw LCA employer names with rotary ==='
SELECT employer_fein, employer_name, count(*) AS filings
FROM public.lca_cases
WHERE employer_name ILIKE '%rotary%'
GROUP BY 1, 2
ORDER BY filings DESC
LIMIT 20;
