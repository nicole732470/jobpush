BEGIN;

WITH rejected AS (
    UPDATE jobpush.career_sites site
    SET verification_status = 'rejected',
        crawl_enabled = FALSE,
        crawl_status = 'paused',
        next_crawl_at = NULL,
        review_notes = concat_ws('; ', site.review_notes, 'Rejected persistent 404 verified site by 125; likely wrong or stale ATS slug'),
        updated_at = now()
    FROM jobpush.crawl_targets target
    WHERE target.consolidation_key = site.consolidation_key
      AND target.enabled
      AND target.priority_tier = 'P1'
      AND site.verification_status = 'verified'
      AND site.crawl_enabled
      AND site.crawl_status = 'failed'
      AND site.consecutive_failures >= 2
      AND site.last_error ILIKE '%404%'
    RETURNING site.consolidation_key, site.source_type
)
UPDATE jobpush.crawl_targets target
SET discovery_status = 'review_pending',
    next_discovery_at = NULL,
    updated_at = now()
WHERE target.consolidation_key IN (SELECT consolidation_key FROM rejected)
  AND NOT EXISTS (
      SELECT 1
      FROM jobpush.career_sites site
      WHERE site.consolidation_key = target.consolidation_key
        AND site.verification_status = 'verified'
        AND site.crawl_enabled
  );

COMMIT;

SELECT source_type, count(*) AS rejected_sites
FROM jobpush.career_sites
WHERE review_notes LIKE '%Rejected persistent 404 verified site by 125%'
GROUP BY 1
ORDER BY rejected_sites DESC, source_type;
