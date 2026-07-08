\pset pager off

BEGIN;

-- Chronic iCIMS/generic timeouts: stop burning serial crawl slots after repeated failure.
UPDATE jobpush.career_sites site
SET crawl_enabled = FALSE,
    crawl_status = 'paused',
    verification_status = CASE
        WHEN site.reviewed_by LIKE 'system:%' THEN 'unverified'
        ELSE site.verification_status
    END,
    review_notes = concat_ws(
        '; ',
        site.review_notes,
        'Quarantined chronic timeout after repeated crawl failure (ops/quarantine_p2_chronic_failures)'
    ),
    updated_at = now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.enabled
  AND target.priority_tier = 'P2'
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.source_type IN ('icims', 'generic_html')
  AND site.consecutive_failures >= 2
  AND (
      site.crawl_status = 'failed'
      OR (site.source_type = 'icims' AND site.crawl_status = 'pending')
  )
  AND (
      coalesce(site.last_error, '') ILIKE '%timeout%'
      OR coalesce(site.last_error, '') ILIKE '%timed out%'
      OR coalesce(site.last_error, '') ILIKE '%403%'
      OR coalesce(site.last_error, '') ILIKE '%forbidden%'
  );

-- Workday adapter/payload failures: demote job-detail URLs and malformed board URLs.
UPDATE jobpush.career_sites site
SET verification_status = 'unverified',
    crawl_enabled = FALSE,
    crawl_status = 'pending',
    next_crawl_at = NULL,
    reviewed_by = 'system:p2-workday-payload-cleanup',
    review_notes = concat_ws(
        '; ',
        site.review_notes,
        'Demoted Workday URL after adapter/payload failure; needs board URL rediscovery'
    ),
    updated_at = now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.enabled
  AND target.priority_tier = 'P2'
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.crawl_status = 'failed'
  AND site.source_type = 'workday'
  AND (
      site.site_url ~* 'myworkdayjobs\.com/.*/job/'
      OR coalesce(site.last_error, '') ILIKE '%422%'
      OR coalesce(site.last_error, '') ILIKE '%payload%'
      OR coalesce(site.last_error, '') ILIKE '%cxs%'
      OR coalesce(site.last_error, '') ILIKE '%empty%'
  );

-- Greenhouse stale slugs still marked failed after 404 cleanup.
UPDATE jobpush.career_sites site
SET crawl_enabled = FALSE,
    crawl_status = 'paused',
    verification_status = CASE
        WHEN site.reviewed_by LIKE 'system:%' THEN 'unverified'
        ELSE site.verification_status
    END,
    review_notes = concat_ws(
        '; ',
        site.review_notes,
        'Quarantined stale Greenhouse board after 404 (ops/quarantine_p2_chronic_failures)'
    ),
    updated_at = now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.enabled
  AND target.priority_tier = 'P2'
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.crawl_status = 'failed'
  AND site.source_type = 'greenhouse'
  AND (
      coalesce(site.last_error, '') ILIKE '%404%'
      OR coalesce(site.last_error, '') ILIKE '%HTTP Error 404%'
  );

COMMIT;

SELECT target.priority_tier,
       site.source_type,
       site.crawl_status,
       count(*) AS sites
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier = 'P2'
  AND (
      site.review_notes ILIKE '%quarantine_p2_chronic_failures%'
      OR site.reviewed_by = 'system:p2-workday-payload-cleanup'
  )
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
