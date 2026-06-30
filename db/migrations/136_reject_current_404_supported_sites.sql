\pset pager off

BEGIN;

-- ponytail: confirmed 404 adapter endpoints are stale/wrong candidates, not retry work.
WITH rejected AS (
    UPDATE jobpush.career_sites site
    SET verification_status = 'rejected',
        crawl_enabled = FALSE,
        crawl_status = 'paused',
        next_crawl_at = NULL,
        reviewed_at = now(),
        reviewed_by = 'system:reject-current-404-v1',
        review_notes = concat_ws('; ', site.review_notes, 'Rejected current adapter 404; needs a fresh career-site candidate.'),
        updated_at = now()
    FROM jobpush.crawl_targets target
    WHERE target.consolidation_key = site.consolidation_key
      AND target.enabled
      AND target.priority_tier IN ('P0', 'P1', 'P2', 'P3')
      AND site.verification_status = 'verified'
      AND site.crawl_enabled
      AND site.crawl_status = 'failed'
      AND site.last_error ILIKE '%HTTP Error 404%'
      AND COALESCE(site.reviewed_by, '') NOT LIKE 'nicole%'
      AND COALESCE(site.reviewed_by, '') NOT LIKE 'manual%'
    RETURNING site.consolidation_key
)
UPDATE jobpush.crawl_targets target
SET discovery_status = 'review_pending',
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
WHERE reviewed_by = 'system:reject-current-404-v1'
GROUP BY 1
ORDER BY rejected_sites DESC, source_type;
