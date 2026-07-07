BEGIN;

WITH latest_run AS (
    SELECT DISTINCT ON (run.site_id)
           run.site_id,
           COALESCE(run.error_message, '') AS error_message
    FROM jobpush.crawl_runs run
    ORDER BY run.site_id, run.started_at DESC NULLS LAST, run.run_id DESC
), bad AS (
    SELECT site.site_id
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    LEFT JOIN latest_run USING (site_id)
    WHERE target.enabled
      AND target.priority_tier IN ('P0','P1','P2','P3')
      AND site.source_type = 'workday'
      AND site.verification_status = 'verified'
      AND site.crawl_enabled
      AND site.crawl_status = 'failed'
      AND COALESCE(NULLIF(site.last_error, ''), latest_run.error_message, '') ~* 'HTTP Error (400|422)'
)
UPDATE jobpush.career_sites site
SET verification_status = 'unverified',
    crawl_enabled = FALSE,
    crawl_status = 'pending',
    next_crawl_at = NULL,
    reviewed_by = 'system:bad-workday-cleanup-v1',
    reviewed_at = now(),
    review_notes = concat_ws('; ', site.review_notes, 'Demoted Workday candidate after CXS API 400/422; likely wrong tenant/site or stale candidate'),
    updated_at = now()
FROM bad
WHERE site.site_id = bad.site_id;

COMMIT;

SELECT target.priority_tier, site.source_type, site.verification_status, site.crawl_enabled, site.crawl_status, count(*) AS sites
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.reviewed_by = 'system:bad-workday-cleanup-v1'
GROUP BY 1,2,3,4,5
ORDER BY 1,2,3,4,5;

