\pset pager off

BEGIN;

-- 2026-06-25 had a Tavily provider/key failure batch that left P1 targets as
-- discovery_status='pending' with last_discovery_at populated and no retained
-- candidates. That state prevents the normal discovery runner from retrying,
-- but it is not evidence that no career site exists.
WITH zero_candidate_retry AS (
    SELECT target.consolidation_key
    FROM jobpush.crawl_targets target
    WHERE target.enabled
      AND target.priority_tier = 'P1'
      AND target.discovery_status = 'pending'
      AND target.last_discovery_at >= TIMESTAMPTZ '2026-06-25 00:00:00+00'
      AND target.last_discovery_at <  TIMESTAMPTZ '2026-06-25 00:30:00+00'
      AND NOT EXISTS (
          SELECT 1
          FROM jobpush.career_sites site
          WHERE site.consolidation_key = target.consolidation_key
            AND site.verification_status IN ('verified', 'unverified')
      )
)
UPDATE jobpush.crawl_targets target
SET last_discovery_at = NULL,
    next_discovery_at = NULL,
    last_discovery_error = NULL,
    consecutive_discovery_failures = 0,
    updated_at = now()
FROM zero_candidate_retry retry
WHERE target.consolidation_key = retry.consolidation_key;

COMMIT;

SELECT
    priority_tier,
    discovery_status,
    COUNT(*) FILTER (WHERE last_discovery_at IS NULL) AS retryable_now,
    COUNT(*) AS companies
FROM jobpush.crawl_targets
WHERE enabled
  AND priority_tier IN ('P0', 'P1')
  AND discovery_status IN ('pending', 'retry', 'not_found')
GROUP BY priority_tier, discovery_status
ORDER BY priority_tier, discovery_status;
