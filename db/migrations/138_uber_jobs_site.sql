BEGIN;

-- SmartRecruiters only exposes a stale Test UAT posting for Uber; use official Happydance careers API instead.
UPDATE jobpush.career_sites
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'system:uber-official-site-v1',
    review_notes = concat_ws('; ', review_notes, 'Rejected SmartRecruiters slug; official site is jobs.uber.com Happydance search API.'),
    updated_at = now()
WHERE consolidation_key = 'uber'
  AND source_type = 'smartrecruiters'
  AND verification_status <> 'rejected';

INSERT INTO jobpush.career_sites (
    consolidation_key,
    site_url,
    normalized_domain,
    site_kind,
    source_type,
    source_key,
    target_country_code,
    scope_method,
    candidate_rank,
    candidate_score,
    verification_status,
    crawl_enabled,
    crawl_status,
    discovery_source,
    reviewed_by,
    reviewed_at,
    next_crawl_at,
    created_at,
    updated_at
)
VALUES (
    'uber',
    'https://jobs.uber.com/en/jobs/?radius=1000',
    'jobs.uber.com',
    'ats_feed',
    'uber_jobs',
    'jobs.uber.com',
    'US',
    'local_filter',
    1,
    100,
    'verified',
    TRUE,
    'pending',
    'manual_repair',
    'system:uber-official-site-v1',
    now(),
    now(),
    now(),
    now()
)
ON CONFLICT (consolidation_key, site_url) DO UPDATE
SET
    normalized_domain = EXCLUDED.normalized_domain,
    site_kind = EXCLUDED.site_kind,
    source_type = EXCLUDED.source_type,
    source_key = EXCLUDED.source_key,
    target_country_code = 'US',
    scope_method = 'local_filter',
    candidate_rank = LEAST(coalesce(jobpush.career_sites.candidate_rank, EXCLUDED.candidate_rank), EXCLUDED.candidate_rank),
    candidate_score = GREATEST(coalesce(jobpush.career_sites.candidate_score, 0), EXCLUDED.candidate_score),
    verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    discovery_source = EXCLUDED.discovery_source,
    reviewed_by = EXCLUDED.reviewed_by,
    reviewed_at = now(),
    next_crawl_at = now(),
    last_error = NULL,
    updated_at = now();

UPDATE jobpush.crawl_targets
SET discovery_status = 'found',
    next_discovery_at = NULL,
    updated_at = now()
WHERE consolidation_key = 'uber'
  AND enabled;

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
        WHEN 'P3' THEN 336
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
  AND target.priority_tier IN ('P0', 'P1', 'P2', 'P3')
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.target_country_code = 'US'
  AND site.scope_method <> 'unknown'
  AND site.source_type IN (
      'amazon_jobs', 'apple_jobs', 'cognizant_jobs', 'eightfold', 'generic_html',
      'google_jobs', 'greenhouse', 'icims', 'oracle_cloud', 'workday', 'lever',
      'ashby', 'smartrecruiters', 'workable', 'jobvite', 'paylocity', 'rippling',
      'uber_jobs'
  );

COMMIT;

\pset pager off

SELECT site_id, site_url, source_type, verification_status, crawl_enabled, crawl_status, next_crawl_at
FROM jobpush.career_sites
WHERE consolidation_key = 'uber'
ORDER BY crawl_enabled DESC, source_type, site_id;
