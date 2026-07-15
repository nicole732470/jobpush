\pset pager off

SELECT consolidation_key, canonical_name, crawl_priority_tier, priority_score
FROM jobpush.company_targets_consolidated
WHERE canonical_name ILIKE '%asana%'
   OR consolidation_key ILIKE '%asana%'
ORDER BY priority_score DESC NULLS LAST, canonical_name;

SELECT target.consolidation_key, target.canonical_name, target.priority_tier,
       target.priority_source, target.enabled, target.discovery_status
FROM jobpush.crawl_targets target
WHERE target.canonical_name ILIKE '%asana%'
   OR target.consolidation_key ILIKE '%asana%'
ORDER BY target.canonical_name;

SELECT site.site_id, site.consolidation_key, site.site_url, site.source_type,
       site.source_key, site.verification_status, site.crawl_enabled,
       site.crawl_status, site.next_crawl_at, site.last_error
FROM jobpush.career_sites site
WHERE site.consolidation_key IN (
        SELECT consolidation_key
        FROM jobpush.company_targets_consolidated
        WHERE canonical_name ILIKE '%asana%' OR consolidation_key ILIKE '%asana%'
      )
   OR site.consolidation_key IN (
        SELECT consolidation_key
        FROM jobpush.crawl_targets
        WHERE canonical_name ILIKE '%asana%' OR consolidation_key ILIKE '%asana%'
      )
   OR site.site_url ILIKE '%asana%'
ORDER BY site.consolidation_key, site.site_id;
