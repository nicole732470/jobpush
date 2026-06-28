\pset pager off

WITH failed AS (
    SELECT
        target.priority_tier,
        site.source_type,
        CASE
            WHEN coalesce(site.last_error, '') ILIKE '%404%' THEN 'wrong_or_stale_ats_url'
            WHEN coalesce(site.last_error, '') ILIKE '%429%' OR coalesce(site.last_error, '') ILIKE '%rate%' THEN 'rate_limited'
            WHEN coalesce(site.last_error, '') ILIKE '%timeout%' OR coalesce(site.last_error, '') ILIKE '%timed out%' THEN 'timeout'
            WHEN coalesce(site.last_error, '') ILIKE '%403%' OR coalesce(site.last_error, '') ILIKE '%forbidden%' THEN 'blocked_or_forbidden'
            WHEN coalesce(site.last_error, '') ILIKE '%empty%' OR coalesce(site.last_error, '') ILIKE '%missing title%' THEN 'empty_or_malformed_payload'
            WHEN coalesce(site.last_error, '') ILIKE '%workday%' OR coalesce(site.last_error, '') ILIKE '%422%' THEN 'adapter_endpoint_or_payload'
            WHEN coalesce(site.last_error, '') = '' THEN 'unknown'
            ELSE 'other'
        END AS failure_reason
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P0','P1','P2')
      AND site.verification_status = 'verified'
      AND site.crawl_enabled
      AND site.crawl_status = 'failed'
)
SELECT priority_tier, source_type, failure_reason, count(*) AS failed_sites
FROM failed
GROUP BY 1, 2, 3
ORDER BY failed_sites DESC, priority_tier, source_type, failure_reason;
