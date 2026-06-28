\pset pager off

BEGIN;

SELECT jobpush.set_manual_crawl_priority(
    'amazon',
    'P0',
    'Manual P0: Amazon should be monitored as a highest-priority employer',
    'nicole'
);

SELECT jobpush.set_manual_crawl_priority(
    '45-2588732',
    'P0',
    'Manual P0: Amazon verified US careers feed is attached to this shared crawl row',
    'nicole'
);

COMMIT;

SELECT consolidation_key, canonical_name, priority_tier, priority_source,
       priority_override_reason, priority_score
FROM jobpush.crawl_targets
WHERE consolidation_key = '45-2588732';

SELECT consolidation_key, canonical_name, priority_tier, priority_source,
       priority_override_reason, priority_score
FROM jobpush.crawl_targets
WHERE consolidation_key = 'amazon';
