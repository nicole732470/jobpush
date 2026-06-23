\echo '=== Ulta companies ==='
SELECT fein, name, lca_count FROM public.companies
WHERE fein IN ('46-1142752', '36-4832212')
   OR name ILIKE '%ulta%';

\echo '=== Ulta consolidated ==='
SELECT * FROM jobpush.company_targets_consolidated
WHERE canonical_name ILIKE '%ulta%' OR consolidation_key IN ('46-1142752', '36-4832212');

\echo '=== Ulta career_sites ==='
SELECT site_id, consolidation_key, candidate_rank, site_url, verification_status
FROM jobpush.career_sites
WHERE consolidation_key IN ('46-1142752', '36-4832212')
ORDER BY consolidation_key, candidate_rank;

\echo '=== Ulta crawl_targets ==='
SELECT consolidation_key, canonical_name, priority_tier, discovery_status
FROM jobpush.crawl_targets
WHERE consolidation_key IN ('46-1142752', '36-4832212');

\echo '=== Ulta linkedin matches ==='
SELECT * FROM jobpush.linkedin_top_employer_company_matches
WHERE fein IN ('46-1142752', '36-4832212');
