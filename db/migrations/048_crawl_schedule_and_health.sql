BEGIN;

-- Scheduling is deliberately limited to sites that are both trusted and
-- technically ready. A verified URL alone is not enough: the adapter and US
-- scope must also be known.
CREATE OR REPLACE VIEW jobpush.crawl_schedule_queue AS
SELECT
    target.priority_tier,
    target.priority_score,
    target.consolidation_key,
    target.canonical_name,
    site.site_id,
    site.source_type,
    site.site_url,
    site.scope_method,
    CASE target.priority_tier
        WHEN 'P0' THEN 24
        WHEN 'P1' THEN 72
        WHEN 'P2' THEN 168
    END AS recommended_interval_hours,
    site.last_crawled_at,
    site.last_success_at,
    site.next_crawl_at,
    COALESCE(site.next_crawl_at, now()) <= now() AS is_due,
    site.consecutive_failures,
    site.crawl_status
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier IN ('P0', 'P1', 'P2')
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.target_country_code = 'US'
  AND site.scope_method <> 'unknown'
  AND site.source_type IN ('apple_jobs', 'greenhouse', 'icims', 'oracle_cloud', 'workday');

UPDATE jobpush.career_sites site
SET crawl_interval_hours = CASE target.priority_tier
        WHEN 'P0' THEN 24
        WHEN 'P1' THEN 72
        WHEN 'P2' THEN 168
    END,
    next_crawl_at = COALESCE(
        site.next_crawl_at,
        site.last_success_at + make_interval(hours => CASE target.priority_tier
            WHEN 'P0' THEN 24 WHEN 'P1' THEN 72 WHEN 'P2' THEN 168 END),
        now()
    ),
    updated_at = now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.enabled
  AND target.priority_tier IN ('P0', 'P1', 'P2')
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.target_country_code = 'US'
  AND site.scope_method <> 'unknown'
  AND site.source_type IN ('apple_jobs', 'greenhouse', 'icims', 'oracle_cloud', 'workday');

CREATE OR REPLACE VIEW jobpush.crawl_adapter_health AS
WITH recent AS (
    SELECT
        run.*,
        site.source_type,
        site.consolidation_key,
        row_number() OVER (PARTITION BY run.site_id ORDER BY run.started_at DESC) AS recency
    FROM jobpush.crawl_runs run
    JOIN jobpush.career_sites site USING (site_id)
), aggregate AS (
    SELECT
        source_type,
        count(*) FILTER (WHERE started_at >= now() - interval '7 days') AS runs_7d,
        count(*) FILTER (WHERE started_at >= now() - interval '7 days' AND status = 'succeeded') AS successes_7d,
        count(*) FILTER (WHERE started_at >= now() - interval '7 days' AND status = 'failed') AS failures_7d,
        sum(requests_count) FILTER (WHERE started_at >= now() - interval '7 days') AS requests_7d,
        sum(parsed_job_count) FILTER (WHERE started_at >= now() - interval '7 days') AS parsed_jobs_7d,
        round(avg(latency_ms) FILTER (WHERE started_at >= now() - interval '7 days')) AS avg_latency_ms_7d,
        max(started_at) AS last_run_at
    FROM recent
    GROUP BY source_type
)
SELECT
    source_type,
    runs_7d,
    successes_7d,
    failures_7d,
    CASE WHEN runs_7d = 0 THEN NULL
         ELSE round(successes_7d::numeric / runs_7d, 4) END AS success_rate_7d,
    COALESCE(requests_7d, 0) AS requests_7d,
    COALESCE(parsed_jobs_7d, 0) AS parsed_jobs_7d,
    avg_latency_ms_7d,
    last_run_at
FROM aggregate;

CREATE OR REPLACE VIEW jobpush.crawl_site_alerts AS
SELECT
    queue.priority_tier,
    queue.consolidation_key,
    queue.canonical_name,
    queue.site_id,
    queue.source_type,
    CASE
        WHEN queue.consecutive_failures >= 3 THEN 'repeated_failure'
        WHEN queue.crawl_status = 'succeeded'
             AND NOT EXISTS (
                 SELECT 1 FROM jobpush.job_postings posting
                 WHERE posting.site_id = queue.site_id AND posting.active
             ) THEN 'zero_active_jobs'
        WHEN queue.next_crawl_at < now() - interval '24 hours' THEN 'overdue'
    END AS alert_type,
    queue.consecutive_failures,
    queue.last_crawled_at,
    queue.next_crawl_at
FROM jobpush.crawl_schedule_queue queue
WHERE queue.consecutive_failures >= 3
   OR (queue.crawl_status = 'succeeded' AND NOT EXISTS (
        SELECT 1 FROM jobpush.job_postings posting
        WHERE posting.site_id = queue.site_id AND posting.active
   ))
   OR queue.next_crawl_at < now() - interval '24 hours';

COMMIT;
