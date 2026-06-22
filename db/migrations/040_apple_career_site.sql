BEGIN;

UPDATE jobpush.career_sites
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'nicole',
    review_notes = 'Superseded by confirmed Apple United States jobs search URL',
    updated_at = now()
WHERE consolidation_key = 'apple'
  AND site_url <> 'https://jobs.apple.com/en-us/search?location=united-states-USA';

INSERT INTO jobpush.career_sites (
    consolidation_key, site_url, normalized_domain, site_kind, source_type,
    source_key, discovery_source, verification_status, crawl_enabled,
    crawl_status, target_country_code, next_crawl_at, reviewed_at,
    reviewed_by, review_notes, notes
)
SELECT
    'apple',
    'https://jobs.apple.com/en-us/search?location=united-states-USA',
    'jobs.apple.com',
    'ats_feed',
    'apple_jobs',
    'jobs.apple.com',
    'manual',
    'verified',
    TRUE,
    'pending',
    'US',
    now(),
    now(),
    'nicole',
    'Confirmed Apple official United States jobs search page',
    'Apple custom careers platform; requires apple_jobs adapter'
FROM jobpush.crawl_targets
WHERE consolidation_key = 'apple'
ON CONFLICT (consolidation_key, site_url) DO UPDATE SET
    normalized_domain = EXCLUDED.normalized_domain,
    site_kind = EXCLUDED.site_kind,
    source_type = EXCLUDED.source_type,
    source_key = EXCLUDED.source_key,
    discovery_source = EXCLUDED.discovery_source,
    verification_status = EXCLUDED.verification_status,
    crawl_enabled = EXCLUDED.crawl_enabled,
    crawl_status = 'pending',
    target_country_code = EXCLUDED.target_country_code,
    next_crawl_at = now(),
    reviewed_at = EXCLUDED.reviewed_at,
    reviewed_by = EXCLUDED.reviewed_by,
    review_notes = EXCLUDED.review_notes,
    notes = EXCLUDED.notes,
    updated_at = now();

UPDATE jobpush.crawl_targets
SET discovery_status = 'found',
    next_discovery_at = NULL,
    updated_at = now()
WHERE consolidation_key = 'apple';

COMMIT;
