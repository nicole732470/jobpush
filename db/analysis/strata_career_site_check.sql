\echo '=== Strata company targets ==='
SELECT ct.consolidation_key, ct.canonical_name, cr.priority_tier, cr.priority_score
FROM jobpush.company_targets_consolidated ct
LEFT JOIN jobpush.crawl_targets cr ON cr.consolidation_key = ct.consolidation_key
WHERE ct.canonical_name ILIKE '%strata%decision%'
   OR ct.canonical_name ILIKE '%strata decision%'
   OR ct.consolidation_key ILIKE '%strata%';

\echo '=== Strata crawl_targets ==='
SELECT consolidation_key, discovery_status, priority_tier, enabled
FROM jobpush.crawl_targets
WHERE consolidation_key IN (
    SELECT consolidation_key FROM jobpush.company_targets_consolidated
    WHERE canonical_name ILIKE '%strata%decision%'
       OR canonical_name ILIKE '%strata decision%'
);

\echo '=== Strata career_sites ==='
SELECT site_id, consolidation_key, candidate_rank, site_url,
       verification_status, source_type, crawl_enabled
FROM jobpush.career_sites
WHERE consolidation_key IN (
    SELECT consolidation_key FROM jobpush.company_targets_consolidated
    WHERE canonical_name ILIKE '%strata%decision%'
)
ORDER BY site_id;

\echo '=== Broader strata search ==='
SELECT consolidation_key, canonical_name
FROM jobpush.company_targets_consolidated
WHERE canonical_name ILIKE '%strata%'
ORDER BY canonical_name
LIMIT 20;
