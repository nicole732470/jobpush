\pset pager off

BEGIN;

UPDATE jobpush.crawl_targets
SET enabled = FALSE,
    discovery_status = 'paused',
    next_discovery_at = NULL,
    last_discovery_error = 'Amazon shared feed moved to amazon consolidation_key',
    updated_at = now()
WHERE consolidation_key = '45-2588732';

COMMIT;

SELECT consolidation_key, canonical_name, priority_tier, enabled, discovery_status
FROM jobpush.crawl_targets
WHERE consolidation_key IN ('amazon', '45-2588732');
