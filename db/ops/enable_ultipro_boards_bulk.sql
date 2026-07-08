BEGIN;

-- Enable one company per UltiPro tenant after parser health is confirmed.
WITH ranked AS (
    SELECT
        site.site_id,
        target.priority_tier,
        row_number() OVER (
            PARTITION BY upper(split_part(regexp_replace(site.site_url, '^https?://recruiting\\.ultipro\\.com/', '', 'i'), '/', 1))
            ORDER BY target.priority_score DESC NULLS LAST,
                     site.candidate_rank NULLS LAST,
                     site.site_id
        ) AS tenant_rank
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P0', 'P1', 'P2', 'P3')
      AND site.source_type = 'ultipro'
      AND site.normalized_domain = 'recruiting.ultipro.com'
      AND site.site_url ~* '/jobboard/listjobs$'
      AND site.verification_status = 'unverified'
      AND site.crawl_enabled = FALSE
      AND NOT EXISTS (
          SELECT 1 FROM jobpush.career_sites verified
          WHERE verified.consolidation_key = site.consolidation_key
            AND verified.verification_status = 'verified'
            AND verified.crawl_enabled
      )
), eligible AS (
    SELECT site_id, priority_tier
    FROM ranked
    WHERE tenant_rank = 1
)
UPDATE jobpush.career_sites site
SET verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    target_country_code = 'US',
    scope_method = 'local_filter',
    next_crawl_at = now(),
    crawl_interval_hours = CASE eligible.priority_tier
        WHEN 'P0' THEN 24 WHEN 'P1' THEN 72 WHEN 'P2' THEN 168 ELSE 336 END,
    reviewed_at = now(),
    reviewed_by = 'system:ultipro-parser-bulk-v1',
    review_notes = concat_ws('; ', site.review_notes, 'Bulk-enabled UltiPro board with one company per tenant'),
    updated_at = now()
FROM eligible
WHERE site.site_id = eligible.site_id;

COMMIT;

SELECT target.priority_tier, count(*) AS enabled_sites
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.reviewed_by = 'system:ultipro-parser-bulk-v1'
GROUP BY 1
ORDER BY 1;
