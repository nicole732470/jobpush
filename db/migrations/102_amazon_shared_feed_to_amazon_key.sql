\pset pager off

BEGIN;

UPDATE jobpush.crawl_priority_overrides
SET active = FALSE,
    reason = concat_ws('; ', reason, 'Amazon shared feed moved to amazon consolidation_key'),
    updated_at = now()
WHERE consolidation_key = '45-2588732';

UPDATE jobpush.career_sites
SET consolidation_key = 'amazon',
    crawl_enabled = TRUE,
    verification_status = 'verified',
    source_type = 'amazon_jobs',
    source_key = 'amazon.jobs',
    site_kind = 'ats_feed',
    target_country_code = 'US',
    scope_method = 'server_filter',
    review_notes = concat_ws('; ', review_notes, '102 moved Amazon shared crawl feed to amazon key'),
    updated_at = now()
WHERE site_id = 3366;

UPDATE jobpush.job_postings
SET consolidation_key = 'amazon',
    updated_at = now()
WHERE site_id = 3366;

UPDATE jobpush.crawl_targets
SET discovery_status = 'found',
    next_discovery_at = NULL,
    updated_at = now()
WHERE consolidation_key = 'amazon';

COMMIT;

SELECT target.consolidation_key, target.canonical_name, target.priority_tier,
       target.priority_source, site.site_id, site.source_type, site.crawl_enabled,
       site.last_success_at
FROM jobpush.crawl_targets target
LEFT JOIN jobpush.career_sites site USING (consolidation_key)
WHERE target.consolidation_key IN ('amazon', '45-2588732')
  AND (site.site_id = 3366 OR site.site_id IS NULL)
ORDER BY target.consolidation_key, site.site_id;
