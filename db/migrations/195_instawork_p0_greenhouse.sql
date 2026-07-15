BEGIN;

INSERT INTO jobpush.crawl_priority_overrides (
    consolidation_key, override_tier, reason, created_by, active
)
VALUES (
    'instawork', 'P0',
    'Manual priority: Instawork official Greenhouse board',
    'nicole', TRUE
)
ON CONFLICT (consolidation_key) DO UPDATE SET
    override_tier = EXCLUDED.override_tier,
    reason = EXCLUDED.reason,
    created_by = EXCLUDED.created_by,
    active = TRUE,
    updated_at = now();

INSERT INTO jobpush.crawl_targets (
    consolidation_key, canonical_name, priority_tier, computed_priority_tier,
    priority_source, priority_override_reason, priority_score, enabled,
    discovery_status, next_discovery_at, created_at, updated_at
)
VALUES (
    'instawork', 'Instawork', 'P0', NULL,
    'manual_override', 'Manual priority: Instawork official Greenhouse board',
    0, TRUE, 'found', NULL, now(), now()
)
ON CONFLICT (consolidation_key) DO UPDATE SET
    canonical_name = EXCLUDED.canonical_name,
    priority_tier = 'P0',
    priority_source = 'manual_override',
    priority_override_reason = EXCLUDED.priority_override_reason,
    enabled = TRUE,
    discovery_status = 'found',
    next_discovery_at = NULL,
    updated_at = now();

SELECT jobpush.add_verified_career_site(
    'instawork',
    'https://job-boards.greenhouse.io/instawork',
    'greenhouse',
    'instawork',
    'US',
    'verified_us_only',
    'nicole',
    'Official Instawork Greenhouse job board'
);

COMMIT;

SELECT target.canonical_name, target.priority_tier, target.enabled,
       site.site_id, site.site_url, site.source_type, site.crawl_enabled,
       site.next_crawl_at
FROM jobpush.crawl_targets target
JOIN jobpush.career_sites site USING (consolidation_key)
WHERE target.consolidation_key = 'instawork'
  AND site.site_url = 'https://job-boards.greenhouse.io/instawork';
