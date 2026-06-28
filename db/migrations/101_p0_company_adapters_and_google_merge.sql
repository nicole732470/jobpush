\pset pager off

BEGIN;

-- Operationally merge Alphabet/Google into Google. Keep historical rows, but
-- only the `google` consolidation_key remains active for crawling/dashboard.
UPDATE jobpush.crawl_priority_overrides
SET active = FALSE,
    reason = concat_ws('; ', reason, 'Merged into google consolidation_key'),
    updated_at = now()
WHERE consolidation_key = 'alphabet-google';

UPDATE jobpush.crawl_targets
SET enabled = FALSE,
    discovery_status = 'paused',
    next_discovery_at = NULL,
    last_discovery_error = 'Merged into google consolidation_key',
    updated_at = now()
WHERE consolidation_key = 'alphabet-google';

UPDATE jobpush.job_postings
SET consolidation_key = 'google',
    updated_at = now()
WHERE consolidation_key = 'alphabet-google';

UPDATE jobpush.career_sites
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    review_notes = concat_ws('; ', review_notes, '101 merged into google; duplicate Google careers URL'),
    updated_at = now()
WHERE consolidation_key = 'alphabet-google';

-- P0 company-specific adapters.
UPDATE jobpush.career_sites
SET source_type = 'google_jobs',
    source_key = 'www.google.com',
    site_kind = 'ats_feed',
    target_country_code = 'US',
    scope_method = 'server_filter',
    crawl_status = 'pending',
    next_crawl_at = now(),
    last_error = NULL,
    updated_at = now(),
    review_notes = concat_ws('; ', review_notes, '101 Google Careers HTML adapter')
WHERE consolidation_key = 'google'
  AND site_id = 290;

UPDATE jobpush.career_sites
SET source_type = 'cognizant_jobs',
    source_key = 'careers.cognizant.com',
    site_kind = 'ats_feed',
    target_country_code = 'US',
    scope_method = 'server_filter',
    verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    next_crawl_at = now(),
    last_error = NULL,
    updated_at = now(),
    review_notes = concat_ws('; ', review_notes, '101 Cognizant Careers HTML adapter')
WHERE consolidation_key = '13-3924155'
  AND site_id = 9501;

UPDATE jobpush.career_sites
SET source_type = 'eightfold',
    source_key = 'portal.careers.hsbc.com',
    site_kind = 'ats_feed',
    target_country_code = 'US',
    scope_method = 'server_filter',
    verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    next_crawl_at = now(),
    last_error = NULL,
    updated_at = now(),
    review_notes = concat_ws('; ', review_notes, '101 Eightfold embedded adapter')
WHERE consolidation_key = 'hsbc'
  AND site_id = 9503;

UPDATE jobpush.crawl_targets target
SET discovery_status = 'found',
    next_discovery_at = NULL,
    updated_at = now()
WHERE target.consolidation_key IN ('google', '13-3924155', 'hsbc')
  AND target.enabled;

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
  AND site.source_type IN (
      'amazon_jobs', 'apple_jobs', 'cognizant_jobs', 'eightfold', 'google_jobs',
      'greenhouse', 'icims', 'oracle_cloud', 'workday', 'lever', 'ashby',
      'smartrecruiters', 'workable', 'jobvite', 'paylocity', 'rippling'
  );

COMMIT;

SELECT target.consolidation_key, target.canonical_name, target.priority_tier,
       target.enabled, site.site_id, site.source_type, site.crawl_enabled,
       site.verification_status, site.next_crawl_at
FROM jobpush.crawl_targets target
LEFT JOIN jobpush.career_sites site USING (consolidation_key)
WHERE target.consolidation_key IN ('alphabet-google', 'google', '13-3924155', 'hsbc')
  AND (site.site_id IN (290, 291, 9501, 9503) OR site.site_id IS NULL)
ORDER BY target.consolidation_key, site.site_id;
