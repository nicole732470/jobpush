\echo '=== THE OCC company ==='
SELECT ct.consolidation_key, ct.canonical_name, ct.lca_count, ct.target_role_lca_count,
       ct.priority_score, cr.priority_tier, cr.discovery_status
FROM jobpush.company_targets_consolidated ct
LEFT JOIN jobpush.crawl_targets cr ON cr.consolidation_key = ct.consolidation_key
WHERE ct.canonical_name ILIKE '%options clearing%'
   OR ct.consolidation_key = '36-2756407';

\echo '=== career_sites ==='
SELECT site_id, candidate_rank, site_url, verification_status, source_type, crawl_enabled
FROM jobpush.career_sites
WHERE consolidation_key = '36-2756407'
ORDER BY site_id;

\echo '=== workbench ==='
SELECT consolidation_key, canonical_name, priority_tier, action_status,
       candidate_1_site_id, candidate_1_url, verified_url
FROM jobpush.career_site_review_workbench
WHERE consolidation_key = '36-2756407';

\echo '=== LCA target roles (top titles) ==='
SELECT job_title, soc_code, case_status, count(*) AS filings
FROM public.lca_cases
WHERE employer_fein = '36-2756407'
GROUP BY 1, 2, 3
ORDER BY filings DESC
LIMIT 20;

\echo '=== LCA by year ==='
SELECT date_part('year', received_date)::int AS yr, count(*) AS filings
FROM public.lca_cases
WHERE employer_fein = '36-2756407'
GROUP BY 1 ORDER BY 1;

\echo '=== Score breakdown ==='
SELECT consolidation_key, canonical_name, employer_city, employer_state,
       target_role_score, lca_count_score, chicago_score, salary_score,
       product_role_score, linkedin_top_employer_score, priority_score,
       target_role_min_annual_salary, crawl_priority_tier
FROM jobpush.company_targets_consolidated
WHERE consolidation_key = '36-2756407';

\echo '=== Worksite locations (top) ==='
SELECT worksite_city, worksite_state, count(*) AS filings
FROM public.lca_cases
WHERE employer_fein = '36-2756407'
GROUP BY 1, 2
ORDER BY filings DESC
LIMIT 10;

\echo '=== Recent filings ==='
SELECT received_date, job_title, worksite_city, worksite_state, case_status
FROM public.lca_cases
WHERE employer_fein = '36-2756407'
ORDER BY received_date DESC
LIMIT 8;
