\echo '=== Ulta career_sites ==='
SELECT site_id, consolidation_key, candidate_rank, site_url,
       verification_status, crawl_enabled, candidate_score
FROM jobpush.career_sites
WHERE consolidation_key = 'ulta'
ORDER BY candidate_rank, site_id;

\echo '=== Ulta review queue ==='
SELECT * FROM jobpush.career_site_review_workbench
WHERE consolidation_key = 'ulta';

\echo '=== Ulta crawl_targets ==='
SELECT consolidation_key, discovery_status, priority_tier
FROM jobpush.crawl_targets WHERE consolidation_key = 'ulta';
