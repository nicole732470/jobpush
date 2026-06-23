BEGIN;

INSERT INTO jobpush.crawl_priority_overrides (
    consolidation_key, override_tier, reason, created_by, active
)
VALUES (
    'accenture',
    'P0',
    'Manual highest-priority Accenture selection',
    'nicole',
    TRUE
)
ON CONFLICT (consolidation_key) DO UPDATE SET
    override_tier = EXCLUDED.override_tier,
    reason = EXCLUDED.reason,
    created_by = EXCLUDED.created_by,
    active = TRUE,
    updated_at = now();

UPDATE jobpush.career_sites
SET
    site_url = 'https://accenture.wd103.myworkdayjobs.com/AccentureCareers?locationCountry=bc33aa3152ec42d4995f4791a106ed09',
    normalized_domain = 'accenture.wd103.myworkdayjobs.com',
    site_kind = 'ats_feed',
    source_type = 'workday',
    source_key = 'accenture.wd103.myworkdayjobs.com',
    discovery_source = 'manual',
    verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    target_country_code = 'US',
    scope_method = 'server_filter',
    next_crawl_at = now(),
    reviewed_at = now(),
    reviewed_by = 'nicole',
    review_notes = 'Confirmed Accenture Workday careers board with United States location filter',
    notes = 'Workday locationCountry filter bc33aa3152ec42d4995f4791a106ed09 = United States',
    updated_at = now()
WHERE site_id = 140
  AND consolidation_key = 'accenture';

UPDATE jobpush.career_sites
SET
    verification_status = 'rejected',
    crawl_enabled = FALSE,
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'nicole',
    review_notes = 'Superseded by confirmed Accenture Workday US careers URL',
    updated_at = now()
WHERE consolidation_key = 'accenture'
  AND site_id <> 140
  AND verification_status = 'unverified';

UPDATE jobpush.crawl_targets
SET
    discovery_status = 'found',
    next_discovery_at = NULL,
    updated_at = now()
WHERE consolidation_key = 'accenture';

COMMIT;
