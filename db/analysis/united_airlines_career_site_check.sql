\echo '=== United Airlines company ==='
SELECT ct.consolidation_key, ct.canonical_name, cr.priority_tier, cr.discovery_status
FROM jobpush.company_targets_consolidated ct
LEFT JOIN jobpush.crawl_targets cr ON cr.consolidation_key = ct.consolidation_key
WHERE ct.canonical_name ILIKE '%united airline%'
   OR ct.canonical_name ILIKE '%united airlines%';

\echo '=== United career_sites ==='
SELECT site_id, consolidation_key, candidate_rank, site_url,
       verification_status, source_type, crawl_enabled
FROM jobpush.career_sites
WHERE consolidation_key IN (
    SELECT consolidation_key FROM jobpush.company_targets_consolidated
    WHERE canonical_name ILIKE '%united airline%'
)
ORDER BY site_id;

\echo '=== United review queue ==='
SELECT * FROM jobpush.career_site_company_review_queue
WHERE canonical_name ILIKE '%united airline%';
