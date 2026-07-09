BEGIN;

SELECT jobpush.set_manual_crawl_priority(
    '91-1144442',
    'P0',
    'Nicole confirmed Microsoft as manual P0 on 2026-07-08'
);

UPDATE jobpush.career_sites
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    next_crawl_at = NULL,
    review_notes = concat_ws('; ', review_notes, 'Superseded by Nicole confirmed Microsoft Eightfold US careers URL on 2026-07-08.'),
    updated_at = now()
WHERE consolidation_key = '91-1144442'
  AND verification_status = 'verified'
  AND site_url <> 'https://apply.careers.microsoft.com/careers?start=0&location=United+States&pid=1970393556874355&sort_by=distance&filter_include_remote=1';

INSERT INTO jobpush.career_sites (
    consolidation_key,
    site_url,
    normalized_domain,
    site_kind,
    source_type,
    source_key,
    discovery_source,
    verification_status,
    crawl_enabled,
    crawl_status,
    target_country_code,
    scope_method,
    candidate_rank,
    candidate_score,
    crawl_interval_hours,
    next_crawl_at,
    reviewed_at,
    reviewed_by,
    review_notes,
    created_at,
    updated_at
) VALUES (
    '91-1144442',
    'https://apply.careers.microsoft.com/careers?start=0&location=United+States&pid=1970393556874355&sort_by=distance&filter_include_remote=1',
    'apply.careers.microsoft.com',
    'ats_feed',
    'eightfold',
    'apply.careers.microsoft.com',
    'manual_dashboard',
    'verified',
    TRUE,
    'pending',
    'US',
    'server_filter',
    1,
    100,
    24,
    now(),
    now(),
    'nicole',
    'Nicole confirmed Microsoft official US careers URL; Eightfold parser tested locally.',
    now(),
    now()
)
ON CONFLICT (consolidation_key, site_url) DO UPDATE SET
    normalized_domain = EXCLUDED.normalized_domain,
    site_kind = EXCLUDED.site_kind,
    source_type = EXCLUDED.source_type,
    source_key = EXCLUDED.source_key,
    discovery_source = EXCLUDED.discovery_source,
    verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    target_country_code = 'US',
    scope_method = 'server_filter',
    candidate_rank = 1,
    candidate_score = GREATEST(coalesce(jobpush.career_sites.candidate_score, 0), 100),
    crawl_interval_hours = 24,
    next_crawl_at = now(),
    reviewed_at = now(),
    reviewed_by = 'nicole',
    review_notes = EXCLUDED.review_notes,
    last_error = NULL,
    updated_at = now();

UPDATE jobpush.career_sites
SET source_type = 'phenom',
    source_key = 'careers.united.com',
    site_kind = 'ats_feed',
    target_country_code = 'US',
    scope_method = 'local_filter',
    crawl_interval_hours = 24,
    next_crawl_at = now(),
    crawl_status = 'pending',
    last_error = NULL,
    review_notes = concat_ws('; ', review_notes, 'Use Phenom parser for United search results.'),
    updated_at = now()
WHERE consolidation_key = '74-2099724'
  AND site_url = 'https://careers.united.com/us/en/search-results';

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
      'ultipro', 'jobscore', 'applicantpro', 'dover', 'catsone', 'trakstar',
      'breezy', 'applytojob', 'phenom'
  );

COMMIT;

SELECT target.priority_tier, target.canonical_name, site.source_type, site.verification_status,
       site.crawl_enabled, site.crawl_status, site.next_crawl_at, site.site_url
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.consolidation_key IN ('91-1144442', '74-2099724')
  AND site.verification_status = 'verified'
ORDER BY target.canonical_name, site.source_type, site.site_id;
