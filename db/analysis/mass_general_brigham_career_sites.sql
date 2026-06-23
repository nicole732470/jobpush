\echo '=== Mass General Brigham review queue ==='
SELECT *
FROM jobpush.career_site_review_workbench
WHERE canonical_name ILIKE '%mass general%brigham%'
   OR consolidation_key = 'mass-general-brigham';

\echo '=== Mass General Brigham all career_sites rows ==='
SELECT site_id, consolidation_key, candidate_rank, candidate_score,
       site_url, normalized_domain, site_kind, source_type,
       verification_status, crawl_enabled, discovery_source,
       evidence_title, reviewed_by, review_notes
FROM jobpush.career_sites
WHERE consolidation_key = 'mass-general-brigham'
ORDER BY candidate_rank NULLS LAST, site_id;

\echo '=== crawl_targets row ==='
SELECT consolidation_key, canonical_name, priority_tier, priority_score,
       discovery_status, discovery_attempts, last_discovery_error
FROM jobpush.crawl_targets
WHERE consolidation_key = 'mass-general-brigham';
