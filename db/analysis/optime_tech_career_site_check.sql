\echo '=== OPTIME-TECH company ==='
SELECT ct.consolidation_key, ct.canonical_name, cr.priority_tier, cr.discovery_status
FROM jobpush.company_targets_consolidated ct
LEFT JOIN jobpush.crawl_targets cr ON cr.consolidation_key = ct.consolidation_key
WHERE ct.canonical_name ILIKE '%optime%tech%'
   OR ct.consolidation_key ILIKE '%optime%';

\echo '=== career_sites ==='
SELECT site_id, consolidation_key, candidate_rank, site_url,
       verification_status, source_type, crawl_enabled
FROM jobpush.career_sites
WHERE consolidation_key IN (
    SELECT consolidation_key FROM jobpush.company_targets_consolidated
    WHERE canonical_name ILIKE '%optime%tech%'
)
ORDER BY site_id;

\echo '=== workbench ==='
SELECT * FROM jobpush.career_site_review_workbench
WHERE canonical_name ILIKE '%optime%tech%';
