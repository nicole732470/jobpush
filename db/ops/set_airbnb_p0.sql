\pset pager off

BEGIN;

SELECT jobpush.set_manual_crawl_priority(
    '26-3051428',
    'P0',
    'Nicole manual P0: Airbnb on 2026-07-09',
    'nicole'
);

UPDATE jobpush.crawl_targets
SET discovery_status = 'found',
    next_discovery_at = NULL,
    updated_at = now()
WHERE consolidation_key = '26-3051428';

UPDATE jobpush.career_sites site
SET crawl_interval_hours = 24,
    next_crawl_at = COALESCE(site.next_crawl_at, now()),
    updated_at = now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.consolidation_key = '26-3051428'
  AND site.verification_status = 'verified'
  AND site.crawl_enabled;

COMMIT;

SELECT target.consolidation_key,
       target.canonical_name,
       target.priority_tier,
       target.priority_source,
       target.priority_override_reason,
       consolidated.crawl_priority_tier,
       consolidated.lca_count
FROM jobpush.crawl_targets target
JOIN jobpush.company_targets_consolidated consolidated
  ON consolidated.consolidation_key = target.consolidation_key
WHERE target.consolidation_key = '26-3051428';

SELECT cs.site_id,
       ct.canonical_name,
       cs.site_url,
       cs.source_type,
       cs.verification_status,
       cs.crawl_enabled,
       cs.crawl_status,
       cs.crawl_interval_hours,
       cs.next_crawl_at
FROM jobpush.career_sites cs
JOIN jobpush.crawl_targets ct ON ct.consolidation_key = cs.consolidation_key
WHERE ct.consolidation_key = '26-3051428'
  AND cs.crawl_enabled = TRUE
ORDER BY cs.site_url;
