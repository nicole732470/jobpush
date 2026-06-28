\pset pager off

BEGIN;

-- Scale website selection without making Nicole manually verify thousands of
-- companies. Human labels remain authoritative; this only promotes rank-1
-- structured ATS candidates when no verified site already exists.
WITH eligible AS (
    SELECT site.site_id
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P0', 'P1')
      AND site.verification_status = 'unverified'
      AND site.candidate_rank = 1
      AND (
          site.source_type IN ('amazon_jobs', 'greenhouse', 'workday', 'lever', 'ashby', 'smartrecruiters', 'oracle_cloud')
          OR (site.source_type = 'workable' AND site.normalized_domain = 'apply.workable.com')
          OR (site.source_type = 'jobvite' AND site.normalized_domain = 'jobs.jobvite.com')
          OR (site.source_type = 'paylocity' AND site.normalized_domain = 'recruiting.paylocity.com')
      )
      AND NOT EXISTS (
          SELECT 1
          FROM jobpush.career_sites verified
          WHERE verified.consolidation_key = site.consolidation_key
            AND verified.verification_status = 'verified'
      )
)
UPDATE jobpush.career_sites site
SET verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    target_country_code = 'US',
    scope_method = 'local_filter',
    next_crawl_at = now(),
    reviewed_at = now(),
    reviewed_by = 'system:structured-ats-rank1-v3',
    review_notes = 'Auto-trusted rank-1 structured ATS candidate after discovery; human labels override this, monitor crawl health and entity mismatch',
    updated_at = now()
FROM eligible
WHERE site.site_id = eligible.site_id;

UPDATE jobpush.crawl_targets target
SET discovery_status = 'found',
    next_discovery_at = NULL,
    updated_at = now()
WHERE EXISTS (
    SELECT 1
    FROM jobpush.career_sites site
    WHERE site.consolidation_key = target.consolidation_key
      AND site.verification_status = 'verified'
      AND site.reviewed_by = 'system:structured-ats-rank1-v3'
);

UPDATE jobpush.career_sites site
SET crawl_interval_hours = CASE target.priority_tier
        WHEN 'P0' THEN 24
        WHEN 'P1' THEN 72
        WHEN 'P2' THEN 168
    END,
    next_crawl_at = COALESCE(site.next_crawl_at, now()),
    updated_at = now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.enabled
  AND target.priority_tier IN ('P0', 'P1', 'P2')
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.target_country_code = 'US'
  AND site.scope_method <> 'unknown'
  AND site.source_type IN (
      'amazon_jobs', 'apple_jobs', 'greenhouse', 'icims', 'oracle_cloud', 'workday',
      'lever', 'ashby', 'smartrecruiters', 'workable', 'jobvite', 'paylocity'
  );

COMMIT;

SELECT reviewed_by, source_type, count(*) AS newly_or_previously_auto_verified
FROM jobpush.career_sites
WHERE reviewed_by = 'system:structured-ats-rank1-v3'
GROUP BY 1, 2
ORDER BY 2;
