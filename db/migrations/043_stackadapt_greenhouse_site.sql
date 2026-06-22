BEGIN;

UPDATE jobpush.career_sites
SET verification_status = 'rejected', crawl_enabled = FALSE, next_crawl_at = NULL,
    reviewed_at = now(), reviewed_by = 'nicole',
    review_notes = 'Superseded by confirmed StackAdapt US-filtered Greenhouse board',
    updated_at = now()
WHERE consolidation_key = '30-1005380' AND site_id <> 111;

UPDATE jobpush.career_sites
SET site_url = 'https://job-boards.greenhouse.io/stackadapt?offices%5B%5D=4008441009',
    normalized_domain = 'job-boards.greenhouse.io', site_kind = 'ats_feed',
    source_type = 'greenhouse', source_key = 'stackadapt', discovery_source = 'manual',
    verification_status = 'verified', crawl_enabled = TRUE, crawl_status = 'pending',
    target_country_code = 'US', next_crawl_at = now(), reviewed_at = now(),
    reviewed_by = 'nicole',
    review_notes = 'Confirmed official StackAdapt Greenhouse board with United States office filter',
    notes = 'Greenhouse API ignores office query; adapter filters job offices by office id 4008441009',
    updated_at = now()
WHERE site_id = 111 AND consolidation_key = '30-1005380';

UPDATE jobpush.crawl_targets
SET discovery_status = 'found', next_discovery_at = NULL, updated_at = now()
WHERE consolidation_key = '30-1005380';

COMMIT;
