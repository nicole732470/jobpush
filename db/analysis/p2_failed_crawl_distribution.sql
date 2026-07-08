\pset pager off

\echo '=== P2 due crawl queue ==='
SELECT source_type, count(*) AS due_sites
FROM jobpush.crawl_schedule_queue
WHERE priority_tier = 'P2' AND is_due AND crawl_status <> 'running'
GROUP BY 1
ORDER BY due_sites DESC, source_type;

\echo '=== P2 current failed by source + reason ==='
WITH failed AS (
    SELECT
        site.source_type,
        CASE
            WHEN coalesce(site.last_error, '') ILIKE '%404%' THEN 'stale_url_404'
            WHEN coalesce(site.last_error, '') ILIKE '%429%' OR coalesce(site.last_error, '') ILIKE '%rate%' THEN 'rate_limited'
            WHEN coalesce(site.last_error, '') ILIKE '%timeout%' OR coalesce(site.last_error, '') ILIKE '%timed out%' THEN 'timeout'
            WHEN coalesce(site.last_error, '') ILIKE '%403%' OR coalesce(site.last_error, '') ILIKE '%forbidden%' THEN 'blocked'
            WHEN site.source_type = 'workday'
              AND (
                  coalesce(site.last_error, '') ILIKE '%422%'
                  OR coalesce(site.last_error, '') ILIKE '%payload%'
                  OR coalesce(site.last_error, '') ILIKE '%cxs%'
              ) THEN 'workday_payload'
            ELSE 'other'
        END AS failure_reason,
        count(*) AS sites
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier = 'P2'
      AND site.verification_status = 'verified'
      AND site.crawl_enabled
      AND site.crawl_status = 'failed'
    GROUP BY 1, 2
)
SELECT * FROM failed ORDER BY sites DESC, source_type, failure_reason;

\echo '=== P2 unenabled structured candidates (auto-trust eligible types) ==='
SELECT site.source_type, count(DISTINCT target.consolidation_key) AS companies
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier = 'P2'
  AND site.verification_status = 'unverified'
  AND NOT site.crawl_enabled
  AND site.source_type IN ('workday', 'workable', 'icims', 'greenhouse', 'lever', 'ashby', 'smartrecruiters', 'ultipro')
GROUP BY 1
ORDER BY companies DESC;
