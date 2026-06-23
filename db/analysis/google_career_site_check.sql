\echo '=== Google company targets ==='
SELECT ct.consolidation_key, ct.canonical_name, cr.priority_tier, cr.discovery_status
FROM jobpush.company_targets_consolidated ct
LEFT JOIN jobpush.crawl_targets cr ON cr.consolidation_key = ct.consolidation_key
WHERE ct.consolidation_key IN ('google', 'alphabet-google')
   OR ct.canonical_name ILIKE '%google%'
ORDER BY ct.consolidation_key;

\echo '=== Google crawl_targets ==='
SELECT consolidation_key, canonical_name, discovery_status, priority_tier, enabled
FROM jobpush.crawl_targets
WHERE consolidation_key IN ('google', 'alphabet-google')
   OR canonical_name ILIKE '%google%';

\echo '=== Google career_sites ==='
SELECT site_id, consolidation_key, candidate_rank, site_url,
       verification_status, source_type, crawl_enabled
FROM jobpush.career_sites
WHERE consolidation_key IN ('google', 'alphabet-google')
ORDER BY site_id;

\echo '=== Google review queue ==='
SELECT * FROM jobpush.career_site_company_review_queue
WHERE consolidation_key IN ('google', 'alphabet-google');
