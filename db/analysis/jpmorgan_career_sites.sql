\echo '=== JPMorgan consolidated ==='
SELECT consolidation_key, canonical_name, priority_score, crawl_priority_tier
FROM jobpush.company_targets_consolidated
WHERE canonical_name ILIKE '%jpmorgan%'
   OR consolidation_key ILIKE '%jpmorgan%'
ORDER BY lca_count DESC
LIMIT 5;

\echo '=== JPMorgan career_sites ==='
SELECT site_id, consolidation_key, candidate_rank, site_url, source_type,
       verification_status, crawl_enabled, evidence_title
FROM jobpush.career_sites
WHERE consolidation_key IN (
    SELECT consolidation_key FROM jobpush.company_targets_consolidated
    WHERE canonical_name ILIKE '%jpmorgan%'
)
   OR consolidation_key ILIKE '%jpmorgan%'
ORDER BY consolidation_key, candidate_rank, site_id;

\echo '=== JPMorgan review queue ==='
SELECT * FROM jobpush.career_site_company_review_queue
WHERE canonical_name ILIKE '%jpmorgan%';

\echo '=== JPMorgan crawl_targets ==='
SELECT consolidation_key, canonical_name, discovery_status, priority_tier
FROM jobpush.crawl_targets
WHERE canonical_name ILIKE '%jpmorgan%';
