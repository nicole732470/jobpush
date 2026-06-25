\pset pager off

\echo '=== Latest failed discovery run ==='
WITH latest AS (
    SELECT run_id
    FROM jobpush.career_site_discovery_runs
    WHERE error_count > 0
    ORDER BY started_at DESC
    LIMIT 1
)
SELECT run_id, cohort, target_count, candidate_count, error_count,
       estimated_credits, status, started_at, finished_at
FROM jobpush.career_site_discovery_runs
WHERE run_id = (SELECT run_id FROM latest);

\echo '=== Current discovery target status after failed run ==='
SELECT priority_tier, discovery_status, count(*) AS companies
FROM jobpush.crawl_targets
WHERE enabled AND priority_tier IN ('P0','P1')
GROUP BY 1,2
ORDER BY 1,2;

\echo '=== Sample current discovery errors ==='
SELECT priority_tier, canonical_name, left(last_discovery_error, 500) AS last_discovery_error
FROM jobpush.crawl_targets
WHERE enabled
  AND priority_tier IN ('P0','P1')
  AND discovery_status = 'retry'
  AND last_discovery_error IS NOT NULL
ORDER BY updated_at DESC
LIMIT 20;
