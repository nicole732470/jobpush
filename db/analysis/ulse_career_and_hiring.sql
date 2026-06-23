\echo '=== ULSE company ==='
SELECT ct.consolidation_key, ct.canonical_name, ct.employer_city, ct.employer_state,
       ct.lca_count, ct.target_role_lca_count, ct.priority_score,
       cr.priority_tier, cr.discovery_status
FROM jobpush.company_targets_consolidated ct
LEFT JOIN jobpush.crawl_targets cr ON cr.consolidation_key = ct.consolidation_key
WHERE ct.canonical_name ILIKE '%ulse%'
   OR ct.consolidation_key = '30-1211139';

\echo '=== career_sites ==='
SELECT site_id, candidate_rank, site_url, verification_status, source_type, crawl_enabled
FROM jobpush.career_sites WHERE consolidation_key = '30-1211139' ORDER BY site_id;

\echo '=== workbench ==='
SELECT priority_tier, action_status, candidate_1_url, verified_url
FROM jobpush.career_site_review_workbench WHERE consolidation_key = '30-1211139';

\echo '=== LCA top titles ==='
SELECT job_title, soc_code, count(*) AS filings
FROM public.lca_cases WHERE employer_fein = '30-1211139'
GROUP BY 1, 2 ORDER BY filings DESC LIMIT 15;

\echo '=== LCA by year ==='
SELECT date_part('year', received_date)::int AS yr, count(*) AS filings
FROM public.lca_cases WHERE employer_fein = '30-1211139'
GROUP BY 1 ORDER BY 1;

\echo '=== Recent filings ==='
SELECT received_date, job_title, worksite_city, worksite_state, case_status
FROM public.lca_cases WHERE employer_fein = '30-1211139'
ORDER BY received_date DESC LIMIT 8;
