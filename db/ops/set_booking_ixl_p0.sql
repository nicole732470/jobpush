\pset pager off

BEGIN;

SELECT jobpush.set_manual_crawl_priority(
    '90-0863533',
    'P0',
    'Nicole manual P0: Booking.com on 2026-07-09',
    'nicole'
);

SELECT jobpush.set_manual_crawl_priority(
    '94-3321802',
    'P0',
    'Nicole manual P0: IXL Learning on 2026-07-09',
    'nicole'
);

UPDATE jobpush.crawl_targets
SET discovery_status = 'found',
    next_discovery_at = NULL,
    updated_at = now()
WHERE consolidation_key IN ('90-0863533', '94-3321802');

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
WHERE target.consolidation_key IN ('90-0863533', '94-3321802')
ORDER BY target.canonical_name;

SELECT cs.site_id,
       ct.canonical_name,
       cs.site_url,
       cs.verification_status,
       cs.crawl_enabled,
       cs.crawl_status,
       cs.next_crawl_at
FROM jobpush.career_sites cs
JOIN jobpush.crawl_targets ct ON ct.consolidation_key = cs.consolidation_key
WHERE ct.consolidation_key IN ('90-0863533', '94-3321802')
  AND cs.crawl_enabled = TRUE
ORDER BY ct.canonical_name, cs.site_url;
