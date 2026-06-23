-- Accenture: P0 override + verified Workday US careers URL.

BEGIN;

INSERT INTO jobpush.crawl_priority_overrides (
    consolidation_key, override_tier, reason, created_by, active
)
VALUES (
    'accenture', 'P0', 'Manual highest-priority Accenture selection', 'nicole', TRUE
)
ON CONFLICT (consolidation_key) DO UPDATE SET
    override_tier = EXCLUDED.override_tier,
    reason = EXCLUDED.reason,
    active = TRUE,
    updated_at = now();

UPDATE jobpush.career_sites
SET
    site_url = 'https://accenture.wd103.myworkdayjobs.com/AccentureCareers?locationCountry=bc33aa3152ec42d4995f4791a106ed09',
    verification_status = 'verified',
    crawl_enabled = TRUE,
    target_country_code = 'US',
    scope_method = 'server_filter',
    reviewed_at = now(),
    reviewed_by = 'nicole',
    updated_at = now()
WHERE site_id = 140 AND consolidation_key = 'accenture';

UPDATE jobpush.career_sites
SET verification_status = 'rejected', crawl_enabled = FALSE, updated_at = now()
WHERE consolidation_key = 'accenture' AND site_id <> 140;

COMMIT;
