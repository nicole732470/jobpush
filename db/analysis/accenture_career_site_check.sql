\echo '=== Accenture targets ==='
SELECT ct.consolidation_key, ct.canonical_name, cr.priority_tier, cr.priority_source, cr.discovery_status
FROM jobpush.company_targets_consolidated ct
JOIN jobpush.crawl_targets cr ON cr.consolidation_key = ct.consolidation_key
WHERE ct.consolidation_key = 'accenture';

\echo '=== Accenture career_sites ==='
SELECT site_id, candidate_rank, site_url, verification_status, source_type,
       crawl_enabled, target_country_code, reviewed_by
FROM jobpush.career_sites
WHERE consolidation_key = 'accenture'
ORDER BY site_id;

\echo '=== Accenture workbench ==='
SELECT consolidation_key, priority_tier, action_status, candidate_1_site_id, candidate_1_url, verified_url
FROM jobpush.career_site_review_workbench
WHERE consolidation_key = 'accenture';

\echo '=== P0 override ==='
SELECT * FROM jobpush.crawl_priority_overrides WHERE consolidation_key = 'accenture';
