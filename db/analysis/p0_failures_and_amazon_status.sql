\pset pager off

WITH latest_runs AS (
    SELECT
        run.site_id,
        run.status,
        run.error_code,
        run.error_message,
        run.started_at,
        run.finished_at,
        row_number() OVER (PARTITION BY run.site_id ORDER BY run.started_at DESC NULLS LAST, run.run_id DESC) AS rn
    FROM jobpush.crawl_runs run
)
SELECT
    target.consolidation_key,
    target.canonical_name,
    target.priority_tier,
    target.priority_score,
    site.site_id,
    site.source_type,
    site.crawl_status AS site_crawl_status,
    site.last_success_at,
    site.last_error,
    latest.status AS latest_run_status,
    latest.error_code AS latest_run_error_code,
    left(latest.error_message, 300) AS latest_run_error_message,
    latest.started_at AS latest_run_started_at
FROM jobpush.crawl_targets target
LEFT JOIN jobpush.career_sites site
  ON site.consolidation_key = target.consolidation_key
 AND site.verification_status = 'verified'
 AND site.crawl_enabled
LEFT JOIN latest_runs latest
  ON latest.site_id = site.site_id
 AND latest.rn = 1
WHERE target.enabled
  AND target.priority_tier = 'P0'
  AND site.last_success_at IS NULL
ORDER BY target.priority_score DESC NULLS LAST, target.canonical_name, site.site_id;

SELECT
    target.consolidation_key,
    target.canonical_name,
    target.priority_tier,
    target.priority_source,
    target.priority_score,
    site.site_id,
    site.source_type,
    site.crawl_enabled,
    site.verification_status,
    site.site_url,
    site.last_success_at,
    site.crawl_status
FROM jobpush.crawl_targets target
LEFT JOIN jobpush.career_sites site
  ON site.consolidation_key = target.consolidation_key
 AND site.source_type = 'amazon_jobs'
WHERE target.enabled
  AND (
      target.canonical_name ILIKE '%amazon%'
      OR target.consolidation_key ILIKE '%amazon%'
      OR site.source_type = 'amazon_jobs'
  )
ORDER BY target.priority_tier, target.priority_score DESC NULLS LAST, target.canonical_name;
