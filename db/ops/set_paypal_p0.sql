\pset pager off

BEGIN;

SELECT jobpush.set_manual_crawl_priority(
    '20-8747984',
    'P0',
    'Manual P0: PayPal should be monitored as a highest-priority employer',
    'nicole'
);

SELECT jobpush.set_manual_crawl_priority(
    '77-0510487',
    'P0',
    'Manual P0: PayPal should be monitored as a highest-priority employer',
    'nicole'
);

INSERT INTO jobpush.career_sites (
    consolidation_key, site_url, normalized_domain, site_kind,
    source_type, source_key, discovery_source, verification_status,
    crawl_enabled, crawl_status, target_country_code, scope_method,
    next_crawl_at, reviewed_at, reviewed_by, review_notes, updated_at
) VALUES (
    '77-0510487',
    'https://paypal.eightfold.ai/careers?start=0&location=United+States&pid=274917452620&sort_by=distance&filter_include_remote=1',
    'paypal.eightfold.ai',
    'ats_feed',
    'eightfold',
    'paypal.eightfold.ai',
    'manual_ops',
    'verified',
    TRUE,
    'pending',
    'US',
    'server_filter',
    now(),
    now(),
    'nicole',
    'Manual verified PayPal US Eightfold careers site',
    now()
)
ON CONFLICT (consolidation_key, site_url) DO UPDATE SET
    normalized_domain = EXCLUDED.normalized_domain,
    site_kind = EXCLUDED.site_kind,
    source_type = EXCLUDED.source_type,
    source_key = EXCLUDED.source_key,
    discovery_source = EXCLUDED.discovery_source,
    verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    target_country_code = 'US',
    scope_method = 'server_filter',
    next_crawl_at = now(),
    reviewed_at = now(),
    reviewed_by = 'nicole',
    review_notes = EXCLUDED.review_notes,
    updated_at = now();

UPDATE jobpush.crawl_targets
SET discovery_status = 'found',
    next_discovery_at = NULL,
    updated_at = now()
WHERE consolidation_key IN ('20-8747984', '77-0510487');

COMMIT;

SELECT target.consolidation_key,
       target.canonical_name,
       target.priority_tier,
       target.priority_source,
       site.site_id,
       site.source_type,
       site.verification_status,
       site.crawl_enabled,
       site.crawl_status,
       site.next_crawl_at,
       site.site_url
FROM jobpush.crawl_targets target
LEFT JOIN jobpush.career_sites site
  ON site.consolidation_key = target.consolidation_key
 AND site.site_url = 'https://paypal.eightfold.ai/careers?start=0&location=United+States&pid=274917452620&sort_by=distance&filter_include_remote=1'
WHERE target.consolidation_key IN ('20-8747984', '77-0510487')
ORDER BY target.consolidation_key;
