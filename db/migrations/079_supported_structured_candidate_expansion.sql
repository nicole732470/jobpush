BEGIN;

WITH eligible AS (
    SELECT site.site_id,
           target.priority_tier
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P0', 'P1')
      AND site.verification_status = 'unverified'
      AND site.candidate_rank <= 2
      AND site.source_type IN (
          'apple_jobs', 'greenhouse', 'icims', 'oracle_cloud', 'workday',
          'lever', 'ashby', 'smartrecruiters', 'workable', 'jobvite',
          'paylocity', 'rippling'
      )
      AND site.normalized_domain NOT IN ('icims.com', 'careers.icims.com')
      AND NOT EXISTS (
          SELECT 1
          FROM jobpush.career_sites verified
          WHERE verified.consolidation_key = site.consolidation_key
            AND verified.verification_status = 'verified'
      )
)
UPDATE jobpush.career_sites site
SET verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    target_country_code = 'US',
    scope_method = CASE
        WHEN site.source_type IN ('apple_jobs', 'oracle_cloud') THEN 'server_filter'
        ELSE 'local_filter'
    END,
    next_crawl_at = now(),
    crawl_interval_hours = CASE eligible.priority_tier
        WHEN 'P0' THEN 24
        WHEN 'P1' THEN 72
        ELSE 168
    END,
    reviewed_at = now(),
    reviewed_by = 'system:supported-structured-rank2-v1',
    review_notes = 'Auto-trusted supported structured ATS candidate, candidate_rank<=2, no existing verified site; monitor crawl health',
    updated_at = now()
FROM eligible
WHERE site.site_id = eligible.site_id;

UPDATE jobpush.crawl_targets target
SET discovery_status = 'found',
    next_discovery_at = NULL,
    updated_at = now()
WHERE EXISTS (
    SELECT 1
    FROM jobpush.career_sites site
    WHERE site.consolidation_key = target.consolidation_key
      AND site.verification_status = 'verified'
      AND site.reviewed_by = 'system:supported-structured-rank2-v1'
);

COMMIT;
