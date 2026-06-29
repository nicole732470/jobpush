\pset pager off

BEGIN;

WITH failed AS (
    SELECT site.site_id,
           CASE
               WHEN coalesce(site.last_error, '') ILIKE '%404%' THEN 'wrong_or_stale_ats_url'
               WHEN coalesce(site.last_error, '') ILIKE '%timeout%'
                 OR coalesce(site.last_error, '') ILIKE '%timed out%'
                 OR coalesce(site.last_error, '') ILIKE '%403%'
                 OR coalesce(site.last_error, '') ILIKE '%forbidden%' THEN 'transient_retryable'
               ELSE 'keep_failed'
           END AS action
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P0','P1','P2','P3')
      AND site.verification_status = 'verified'
      AND site.crawl_enabled
      AND site.crawl_status = 'failed'
)
UPDATE jobpush.career_sites site
SET crawl_status = 'pending',
    next_crawl_at = now(),
    review_notes = concat_ws('; ', site.review_notes, 'Retry transient failed crawl via ops/resolve_current_failed_sites'),
    updated_at = now()
FROM failed
WHERE site.site_id = failed.site_id
  AND failed.action = 'transient_retryable';

WITH failed AS (
    SELECT site.site_id
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P0','P1','P2','P3')
      AND site.verification_status = 'verified'
      AND site.crawl_enabled
      AND site.crawl_status = 'failed'
      AND coalesce(site.last_error, '') ILIKE '%404%'
)
UPDATE jobpush.career_sites site
SET verification_status = 'unverified',
    crawl_enabled = FALSE,
    crawl_status = 'pending',
    next_crawl_at = NULL,
    reviewed_by = 'system:failed-site-cleanup',
    review_notes = concat_ws('; ', site.review_notes, 'Demoted stale ATS URL after 404; needs site review/rediscovery'),
    updated_at = now()
FROM failed
WHERE site.site_id = failed.site_id;

COMMIT;

SELECT target.priority_tier, site.source_type, site.verification_status, site.crawl_enabled, site.crawl_status, count(*) AS sites
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier IN ('P0','P1','P2','P3')
  AND (
      site.crawl_status = 'failed'
      OR site.review_notes ILIKE '%resolve_current_failed_sites%'
      OR site.review_notes ILIKE '%Demoted stale ATS URL%'
  )
GROUP BY 1,2,3,4,5
ORDER BY 1,2,3,4,5;
