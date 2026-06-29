BEGIN;

WITH eligible AS (
    SELECT site_id, priority_tier
    FROM (
        SELECT site.site_id,
               target.priority_tier,
               ROW_NUMBER() OVER (
                   PARTITION BY site.consolidation_key, site.source_type
                   ORDER BY site.candidate_rank NULLS LAST, site.candidate_score DESC NULLS LAST, site.site_id
               ) AS site_rank
        FROM jobpush.career_sites site
        JOIN jobpush.crawl_targets target USING (consolidation_key)
        WHERE target.enabled
          AND target.priority_tier IN ('P0', 'P1')
          AND site.verification_status = 'unverified'
          AND site.source_type IN ('amazon_jobs', 'cognizant_jobs')
          AND NOT EXISTS (
              SELECT 1
              FROM jobpush.career_sites verified
              WHERE verified.consolidation_key = site.consolidation_key
                AND verified.verification_status = 'verified'
                AND verified.crawl_enabled
          )
    ) ranked
    WHERE site_rank = 1
)
UPDATE jobpush.career_sites site
SET verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    target_country_code = 'US',
    scope_method = 'server_filter',
    next_crawl_at = now(),
    crawl_interval_hours = CASE eligible.priority_tier
        WHEN 'P0' THEN 24
        WHEN 'P1' THEN 72
        ELSE 168
    END,
    reviewed_at = now(),
    reviewed_by = 'system:supported-company-adapter-v1',
    review_notes = concat_ws('; ', site.review_notes, 'Auto-trusted supported company adapter with US server filter'),
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
      AND site.reviewed_by = 'system:supported-company-adapter-v1'
);

COMMIT;

SELECT priority_tier, source_type, COUNT(*) AS due_sites
FROM jobpush.crawl_schedule_queue
WHERE is_due
GROUP BY 1, 2
ORDER BY 1, 2;
