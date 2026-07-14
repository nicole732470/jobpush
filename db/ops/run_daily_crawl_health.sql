\pset pager off

BEGIN;

CREATE TEMP TABLE health_counts (
    stale_runs_recovered INTEGER DEFAULT 0,
    transient_sites_requeued INTEGER DEFAULT 0,
    stale_urls_demoted INTEGER DEFAULT 0,
    chronic_sites_quarantined INTEGER DEFAULT 0
) ON COMMIT DROP;
INSERT INTO health_counts DEFAULT VALUES;

WITH stale AS (
    UPDATE jobpush.crawl_runs
    SET status='failed', error_code='stale_running_recovered',
        error_message='Daily health check recovered a run still active after 2 hours',
        finished_at=now()
    WHERE status='running' AND started_at < now() - interval '2 hours'
    RETURNING site_id, batch_id
), sites AS (
    UPDATE jobpush.career_sites site
    SET crawl_status='pending', next_crawl_at=now(),
        last_error='stale_running_recovered: daily health check', updated_at=now()
    FROM stale WHERE site.site_id=stale.site_id
    RETURNING site.site_id
), batches AS (
    UPDATE jobpush.crawl_batches batch
    SET status='failed', finished_at=now()
    WHERE batch.status='running' AND batch.started_at < now() - interval '2 hours'
    RETURNING batch.batch_id
)
UPDATE health_counts SET stale_runs_recovered=(SELECT count(*) FROM stale);

WITH requeued AS (
    UPDATE jobpush.career_sites site
    SET crawl_status='pending', next_crawl_at=now() + interval '1 hour',
        review_notes=concat_ws('; ', site.review_notes, 'Daily health: transient failure requeued'),
        updated_at=now()
    FROM jobpush.crawl_targets target
    WHERE target.consolidation_key=site.consolidation_key
      AND target.enabled AND target.priority_tier IN ('P0','P1','P2','P3')
      AND site.verification_status='verified' AND site.crawl_enabled
      AND site.crawl_status='failed' AND site.consecutive_failures < 5
      AND coalesce(site.last_error,'') ~* '(timeout|timed out|403|forbidden|429|rate limit|5[0-9][0-9]|connection|temporar)'
      AND coalesce(site.last_error,'') !~* '404'
    RETURNING site.site_id
)
UPDATE health_counts SET transient_sites_requeued=(SELECT count(*) FROM requeued);

WITH demoted AS (
    UPDATE jobpush.career_sites site
    SET verification_status='unverified', crawl_enabled=FALSE, crawl_status='pending',
        next_crawl_at=NULL, reviewed_by='system:daily-crawl-health',
        review_notes=concat_ws('; ', site.review_notes, 'Daily health: stale 404 URL demoted for rediscovery'),
        updated_at=now()
    FROM jobpush.crawl_targets target
    WHERE target.consolidation_key=site.consolidation_key
      AND target.enabled AND target.priority_tier IN ('P0','P1','P2','P3')
      AND site.verification_status='verified' AND site.crawl_enabled
      AND site.crawl_status='failed' AND coalesce(site.last_error,'') ~* '404'
    RETURNING site.site_id
)
UPDATE health_counts SET stale_urls_demoted=(SELECT count(*) FROM demoted);

WITH quarantined AS (
    UPDATE jobpush.career_sites site
    SET verification_status='unverified', crawl_enabled=FALSE, crawl_status='pending',
        next_crawl_at=NULL, reviewed_by='system:daily-crawl-health',
        review_notes=concat_ws('; ', site.review_notes, 'Daily health: quarantined after 5 consecutive failures'),
        updated_at=now()
    FROM jobpush.crawl_targets target
    WHERE target.consolidation_key=site.consolidation_key
      AND target.enabled AND target.priority_tier IN ('P0','P1','P2','P3')
      AND site.verification_status='verified' AND site.crawl_enabled
      AND site.crawl_status='failed' AND site.consecutive_failures >= 5
    RETURNING site.site_id
)
UPDATE health_counts SET chronic_sites_quarantined=(SELECT count(*) FROM quarantined);

UPDATE jobpush.crawl_health_runs health
SET finished_at=now(), status='succeeded',
    stale_runs_recovered=counts.stale_runs_recovered,
    transient_sites_requeued=counts.transient_sites_requeued,
    stale_urls_demoted=counts.stale_urls_demoted,
    chronic_sites_quarantined=counts.chronic_sites_quarantined,
    failed_sites_remaining=(
        SELECT count(*) FROM jobpush.career_sites
        WHERE verification_status='verified' AND crawl_enabled AND crawl_status='failed'
    ),
    failure_groups=COALESCE((
        SELECT jsonb_agg(to_jsonb(grouped) ORDER BY grouped.sites DESC)
        FROM (
            SELECT source_type,
                   CASE
                     WHEN coalesce(last_error,'') ~* '404' THEN '404'
                     WHEN coalesce(last_error,'') ~* '(timeout|timed out)' THEN 'timeout'
                     WHEN coalesce(last_error,'') ~* '(403|forbidden)' THEN '403'
                     WHEN coalesce(last_error,'') ~* '(429|rate limit)' THEN '429'
                     WHEN coalesce(last_error,'') ~* '5[0-9][0-9]' THEN '5xx'
                     WHEN coalesce(last_error,'') ~* '(zero|empty|no jobs)' THEN 'zero_or_empty'
                     ELSE 'other'
                   END AS failure_type,
                   count(*) AS sites
            FROM jobpush.career_sites
            WHERE verification_status='verified' AND crawl_enabled AND crawl_status='failed'
            GROUP BY 1,2
        ) grouped
    ), '[]'::jsonb)
FROM health_counts counts
WHERE health.health_run_id=:'health_run_id';

COMMIT;

SELECT * FROM jobpush.crawl_health_runs WHERE health_run_id=:'health_run_id';
