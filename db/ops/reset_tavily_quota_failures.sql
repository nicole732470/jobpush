\pset pager off

BEGIN;

-- HTTP 432 is a provider/key/quota failure, not evidence that the company lacks
-- a career site. Put those companies back into the normal pending queue so the
-- next valid key can retry them without waiting a day.
UPDATE jobpush.crawl_targets
SET discovery_status = 'pending',
    next_discovery_at = NULL,
    last_discovery_error = NULL,
    consecutive_discovery_failures = GREATEST(consecutive_discovery_failures - 1, 0),
    updated_at = now()
WHERE enabled
  AND priority_tier IN ('P0', 'P1')
  AND discovery_status = 'retry'
  AND last_discovery_error LIKE 'HTTPError: HTTP Error 432%';

COMMIT;

SELECT priority_tier, discovery_status, count(*) AS companies
FROM jobpush.crawl_targets
WHERE enabled AND priority_tier IN ('P0','P1')
GROUP BY 1, 2
ORDER BY 1, 2;
