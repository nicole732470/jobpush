\echo '=== Adage Technologies ==='
SELECT ct.consolidation_key, ct.canonical_name, ct.employer_city, ct.employer_state,
       ct.lca_count, ct.target_role_lca_count, ct.priority_score,
       ct.target_role_min_annual_salary, ct.salary_score, ct.chicago_score,
       ct.linkedin_top_employer_score, cr.priority_tier, cr.priority_source, cr.discovery_status
FROM jobpush.company_targets_consolidated ct
LEFT JOIN jobpush.crawl_targets cr ON cr.consolidation_key = ct.consolidation_key
WHERE ct.canonical_name ILIKE '%adage%technolog%';

\echo '=== career_sites ==='
SELECT site_id, candidate_rank, site_url, verification_status, source_type, crawl_enabled
FROM jobpush.career_sites
WHERE consolidation_key IN (
    SELECT consolidation_key FROM jobpush.company_targets_consolidated
    WHERE canonical_name ILIKE '%adage%technolog%'
)
ORDER BY site_id;

\echo '=== workbench ==='
SELECT priority_tier, action_status, candidate_1_url, verified_url, potential_p0_signal
FROM jobpush.career_site_review_workbench
WHERE canonical_name ILIKE '%adage%technolog%';

\echo '=== LCA top titles ==='
SELECT job_title, soc_code, count(*) AS filings
FROM public.lca_cases
WHERE employer_fein IN (
    SELECT unnest(member_feins) FROM jobpush.company_targets_consolidated
    WHERE canonical_name ILIKE '%adage%technolog%'
)
GROUP BY 1, 2 ORDER BY filings DESC LIMIT 15;

\echo '=== LCA by year ==='
SELECT date_part('year', received_date)::int AS yr, count(*) AS filings
FROM public.lca_cases
WHERE employer_fein IN (
    SELECT unnest(member_feins) FROM jobpush.company_targets_consolidated
    WHERE canonical_name ILIKE '%adage%technolog%'
)
GROUP BY 1 ORDER BY 1;

\echo '=== Recent filings ==='
SELECT received_date, job_title, worksite_city, worksite_state, case_status
FROM public.lca_cases
WHERE employer_fein IN (
    SELECT unnest(member_feins) FROM jobpush.company_targets_consolidated
    WHERE canonical_name ILIKE '%adage%technolog%'
)
ORDER BY received_date DESC LIMIT 10;
