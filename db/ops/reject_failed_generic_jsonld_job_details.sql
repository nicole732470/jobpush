\pset pager off

BEGIN;

-- These generic-jsonld promotions are single JobPosting detail pages, not boards.
-- Retrying them just burns the due queue; reject and leave discovery open for a board URL.
UPDATE jobpush.career_sites site
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'system:reject-generic-jsonld-job-detail-v1',
    review_notes = concat_ws(
        '; ',
        site.review_notes,
        'Rejected generic JSON-LD job-detail URL after failed first crawls; need a careers listing/board page'
    ),
    updated_at = now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.enabled
  AND target.priority_tier IN ('P2', 'P3')
  AND site.reviewed_by = 'system:generic-jsonld-v1'
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.crawl_status = 'failed'
  AND site.last_success_at IS NULL
  AND (
      site.site_url ~* '/job/'
      OR site.site_url ~* '/jobs/job-id-'
      OR site.site_url ~* '/jobs/[a-z0-9][a-z0-9-]{2,}/?$'
      OR site.site_url ~* '/career/[^/]+$'
      OR site.site_url ~* 'jobs-via-dice'
  );

UPDATE jobpush.crawl_targets target
SET discovery_status = 'review_pending',
    updated_at = now()
WHERE NOT EXISTS (
    SELECT 1
    FROM jobpush.career_sites site
    WHERE site.consolidation_key = target.consolidation_key
      AND site.verification_status = 'verified'
      AND site.crawl_enabled
)
AND EXISTS (
    SELECT 1
    FROM jobpush.career_sites site
    WHERE site.consolidation_key = target.consolidation_key
      AND site.reviewed_by = 'system:reject-generic-jsonld-job-detail-v1'
);

COMMIT;

\echo '=== Rejected generic job-detail pages ==='
SELECT target.priority_tier, count(*) AS rejected
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.reviewed_by = 'system:reject-generic-jsonld-job-detail-v1'
GROUP BY 1
ORDER BY 1;

\echo '=== Remaining failed generic-jsonld (if any) ==='
SELECT target.priority_tier, site.site_id, target.canonical_name, site.site_url, site.crawl_status
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.reviewed_by = 'system:generic-jsonld-v1'
  AND target.priority_tier IN ('P2', 'P3')
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND (site.crawl_status = 'failed' OR site.last_success_at IS NULL)
ORDER BY 1, site.site_id;

\echo '=== Enabled companies with verified crawl site ==='
SELECT target.priority_tier, count(DISTINCT target.consolidation_key) AS enabled_companies
FROM jobpush.crawl_targets target
WHERE target.enabled
  AND target.priority_tier IN ('P2', 'P3')
  AND EXISTS (
      SELECT 1 FROM jobpush.career_sites site
      WHERE site.consolidation_key = target.consolidation_key
        AND site.verification_status = 'verified'
        AND site.crawl_enabled
  )
GROUP BY 1
ORDER BY 1;
