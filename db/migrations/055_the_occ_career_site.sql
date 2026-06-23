BEGIN;

UPDATE jobpush.career_sites
SET
    site_url = 'https://theocc.wd5.myworkdayjobs.com/careers',
    normalized_domain = 'theocc.wd5.myworkdayjobs.com',
    site_kind = 'ats_feed',
    source_type = 'workday',
    source_key = 'theocc.wd5.myworkdayjobs.com',
    discovery_source = 'manual',
    verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    target_country_code = 'US',
    scope_method = 'server_filter',
    next_crawl_at = now(),
    reviewed_at = now(),
    reviewed_by = 'nicole',
    review_notes = 'Confirmed OCC Workday careers board',
    updated_at = now()
WHERE site_id = 274
  AND consolidation_key = '36-2756407';

UPDATE jobpush.career_sites
SET
    verification_status = 'rejected',
    crawl_enabled = FALSE,
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'nicole',
    review_notes = 'Superseded by confirmed OCC Workday careers URL',
    updated_at = now()
WHERE consolidation_key = '36-2756407'
  AND site_id <> 274
  AND verification_status = 'unverified';

UPDATE jobpush.crawl_targets
SET discovery_status = 'found', next_discovery_at = NULL, updated_at = now()
WHERE consolidation_key = '36-2756407';

COMMIT;
