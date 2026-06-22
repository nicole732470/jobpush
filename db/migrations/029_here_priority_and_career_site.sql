BEGIN;

INSERT INTO jobpush.crawl_priority_overrides (
    consolidation_key, override_tier, reason, created_by, active
)
VALUES (
    '77-0080465', 'P0', 'Manual highest-priority company selection', 'nicole', TRUE
)
ON CONFLICT (consolidation_key) DO UPDATE SET
    override_tier = EXCLUDED.override_tier,
    reason = EXCLUDED.reason,
    created_by = EXCLUDED.created_by,
    active = TRUE,
    updated_at = now();

UPDATE jobpush.career_sites
SET
    site_url = 'https://careers-here.icims.com/jobs/search?ss=1&hashed=-435626304',
    normalized_domain = 'careers-here.icims.com',
    site_kind = 'ats_feed',
    source_type = 'icims',
    source_key = 'careers-here.icims.com',
    discovery_source = 'manual',
    verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    next_crawl_at = now(),
    reviewed_at = now(),
    reviewed_by = 'nicole',
    review_notes = 'Confirmed correct HERE North America iCIMS search URL',
    updated_at = now()
WHERE site_id = 78
  AND consolidation_key = '77-0080465';

UPDATE jobpush.career_sites
SET
    verification_status = 'rejected',
    crawl_enabled = FALSE,
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'nicole',
    review_notes = 'Superseded by confirmed HERE iCIMS search URL',
    updated_at = now()
WHERE consolidation_key = '77-0080465'
  AND site_id <> 78
  AND verification_status = 'unverified';

UPDATE jobpush.crawl_targets
SET
    discovery_status = 'found',
    next_discovery_at = NULL,
    updated_at = now()
WHERE consolidation_key = '77-0080465';

COMMIT;
