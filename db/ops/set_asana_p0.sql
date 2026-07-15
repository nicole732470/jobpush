\pset pager off

BEGIN;

-- Asana, Inc. highest-priority manual override.
SELECT jobpush.set_manual_crawl_priority(
    '26-3912448',
    'P0',
    'Manual P0: Asana official careers list https://asana.com/jobs/all',
    'nicole'
);

-- Keep existing Greenhouse site_id/job history; switch canonical URL to Nicole's link.
UPDATE jobpush.career_sites
SET site_url = 'https://asana.com/jobs/all',
    normalized_domain = 'asana.com',
    site_kind = 'ats_feed',
    source_type = 'greenhouse',
    source_key = 'asana',
    discovery_source = 'manual',
    verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    target_country_code = 'US',
    scope_method = 'local_filter',
    crawl_interval_hours = COALESCE(crawl_interval_hours, 24),
    next_crawl_at = now(),
    consecutive_failures = 0,
    last_error = NULL,
    reviewed_at = now(),
    reviewed_by = 'nicole',
    review_notes = 'Manual override: official Asana careers list https://asana.com/jobs/all (Greenhouse board asana)',
    notes = 'Greenhouse API board token=asana; public careers page is asana.com/jobs/all',
    updated_at = now()
WHERE site_id = 12310
  AND consolidation_key = '26-3912448';

-- Reject stale location/university candidates on Asana, Inc.
UPDATE jobpush.career_sites
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'nicole',
    review_notes = 'Rejected: superseded by https://asana.com/jobs/all',
    updated_at = now()
WHERE consolidation_key = '26-3912448'
  AND site_id <> 12310
  AND verification_status IN ('unverified', 'verified');

-- Wrong company had the official Asana jobs/all URL as a candidate.
UPDATE jobpush.career_sites
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'nicole',
    review_notes = 'Rejected: URL belongs to Asana, Inc. (26-3912448), not Asana Partners',
    updated_at = now()
WHERE site_id = 49849
  AND consolidation_key = '87-4051443';

UPDATE jobpush.crawl_targets
SET discovery_status = 'found',
    next_discovery_at = NULL,
    updated_at = now()
WHERE consolidation_key = '26-3912448';

COMMIT;

SELECT target.consolidation_key, target.canonical_name, target.priority_tier,
       target.priority_source, target.priority_override_reason, target.enabled
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = '26-3912448';

SELECT site.site_id, site.site_url, site.source_type, site.source_key,
       site.verification_status, site.crawl_enabled, site.crawl_status,
       site.scope_method, site.next_crawl_at
FROM jobpush.career_sites site
WHERE site.consolidation_key = '26-3912448'
ORDER BY site.verification_status DESC, site.site_id;
