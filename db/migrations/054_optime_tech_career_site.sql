BEGIN;

UPDATE jobpush.career_sites
SET
    verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    discovery_source = 'manual',
    target_country_code = 'US',
    scope_method = 'verified_us_only',
    next_crawl_at = now(),
    reviewed_at = now(),
    reviewed_by = 'nicole',
    review_notes = 'Confirmed official OPTIME-TECH careers page on company domain',
    notes = 'LinkedIn jobs URL is aggregator-only and excluded from crawl targets',
    updated_at = now()
WHERE site_id = 239
  AND consolidation_key = '20-3471277';

UPDATE jobpush.career_sites
SET
    verification_status = 'rejected',
    crawl_enabled = FALSE,
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'nicole',
    review_notes = 'Third-party job aggregator, not official company careers site',
    updated_at = now()
WHERE consolidation_key = '20-3471277'
  AND site_id <> 239
  AND verification_status = 'unverified';

UPDATE jobpush.crawl_targets
SET
    discovery_status = 'found',
    next_discovery_at = NULL,
    updated_at = now()
WHERE consolidation_key = '20-3471277';

COMMIT;
