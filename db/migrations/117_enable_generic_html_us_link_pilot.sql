BEGIN;

WITH eligible AS (
    SELECT site_id, priority_tier
    FROM (
        SELECT
            site.site_id,
            target.priority_tier,
            ROW_NUMBER() OVER (
                PARTITION BY site.consolidation_key
                ORDER BY site.candidate_score DESC NULLS LAST,
                         site.candidate_rank NULLS LAST,
                         site.site_id
            ) AS site_rank,
            ROW_NUMBER() OVER (
                ORDER BY target.priority_score DESC,
                         site.candidate_score DESC NULLS LAST,
                         site.site_id
            ) AS pilot_rank
        FROM jobpush.career_sites site
        JOIN jobpush.crawl_targets target USING (consolidation_key)
        WHERE target.enabled
          AND target.priority_tier = 'P1'
          AND site.source_type = 'generic_html'
          AND site.verification_status = 'unverified'
          AND site.crawl_enabled = FALSE
          AND (
              site.site_url ILIKE '%/careers%'
              OR site.site_url ILIKE '%/career%'
              OR site.site_url ILIKE '%/jobs%'
              OR site.site_url ILIKE '%/job%'
          )
          AND NOT EXISTS (
              SELECT 1
              FROM jobpush.career_sites verified
              WHERE verified.consolidation_key = site.consolidation_key
                AND verified.verification_status = 'verified'
                AND verified.crawl_enabled
          )
    ) ranked
    WHERE site_rank = 1
      AND pilot_rank <= 25
)
UPDATE jobpush.career_sites site
SET verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    target_country_code = 'US',
    scope_method = 'local_filter',
    next_crawl_at = now(),
    crawl_interval_hours = CASE eligible.priority_tier
        WHEN 'P0' THEN 24
        WHEN 'P1' THEN 72
        ELSE 168
    END,
    reviewed_at = now(),
    reviewed_by = 'system:generic-html-us-link-pilot-v1',
    review_notes = concat_ws('; ', site.review_notes, 'Pilot: conservative generic HTML parser requires explicit US location near job link'),
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
      AND site.reviewed_by = 'system:generic-html-us-link-pilot-v1'
);

COMMIT;

SELECT priority_tier, source_type, COUNT(*) AS due_sites
FROM jobpush.crawl_schedule_queue
WHERE is_due
GROUP BY 1, 2
ORDER BY 1, 2;
