\pset pager off

BEGIN;

-- ponytail: Amazon adapter crawls search pages; single job pages waste requests.
UPDATE jobpush.career_sites site
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'system:reject-amazon-job-detail-v1',
    review_notes = 'Rejected Amazon job-detail URL; need an Amazon Jobs search URL instead.',
    updated_at = now()
WHERE source_type = 'amazon_jobs'
  AND site_url ~* 'amazon\.jobs/.*/jobs/[0-9]+/'
  AND COALESCE(reviewed_by, '') NOT LIKE 'nicole%'
  AND COALESCE(reviewed_by, '') NOT LIKE 'manual%';

UPDATE jobpush.crawl_targets target
SET discovery_status = 'review_pending',
    updated_at = now()
WHERE NOT EXISTS (
    SELECT 1
    FROM jobpush.career_sites site
    WHERE site.consolidation_key = target.consolidation_key
      AND site.verification_status = 'verified'
)
AND EXISTS (
    SELECT 1
    FROM jobpush.career_sites site
    WHERE site.consolidation_key = target.consolidation_key
      AND site.reviewed_by = 'system:reject-amazon-job-detail-v1'
);

COMMIT;

SELECT verification_status, reviewed_by, count(*) AS sites
FROM jobpush.career_sites
WHERE source_type = 'amazon_jobs'
  AND site_url ~* 'amazon\.jobs/.*/jobs/[0-9]+/'
GROUP BY 1, 2
ORDER BY 3 DESC;
