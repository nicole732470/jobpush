BEGIN;

WITH eligible AS (
    SELECT site.site_id, site.source_type, target.priority_tier
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier = 'P1'
      AND site.verification_status = 'unverified'
      AND site.candidate_rank = 1
      AND (
          site.source_type = 'cognizant_jobs'
          OR (
              site.source_type = 'icims'
              AND site.normalized_domain <> 'icims.com'
              AND site.site_url !~* '(login|intro|internal|privacy)'
          )
      )
      AND NOT EXISTS (
          SELECT 1
          FROM jobpush.career_sites verified
          WHERE verified.consolidation_key = site.consolidation_key
            AND verified.verification_status = 'verified'
      )
    ORDER BY target.priority_score DESC, site.candidate_score DESC NULLS LAST, site.site_id
    LIMIT 25
)
UPDATE jobpush.career_sites site
SET verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    target_country_code = 'US',
    scope_method = 'local_filter',
    next_crawl_at = now(),
    crawl_interval_hours = CASE eligible.priority_tier
        WHEN 'P1' THEN 72
        ELSE 168
    END,
    reviewed_at = now(),
    reviewed_by = 'system:clean-supported-structured-v1',
    review_notes = concat_ws('; ', site.review_notes, 'Auto-trusted clean supported structured candidate by 124'),
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
      AND site.reviewed_by = 'system:clean-supported-structured-v1'
);

COMMIT;

SELECT priority_tier, source_type, count(*) AS due_sites
FROM jobpush.crawl_schedule_queue
WHERE is_due
GROUP BY 1, 2
ORDER BY 1, 2;
