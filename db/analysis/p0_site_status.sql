\pset pager off
SELECT target.priority_tier, target.canonical_name, site.site_id, site.source_type, site.crawl_status,
       site.crawl_enabled, site.consecutive_failures, site.last_crawled_at, site.last_success_at,
       site.next_crawl_at, left(coalesce(site.last_error,''), 220) AS last_error, site.site_url
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled AND target.priority_tier='P0'
  AND site.verification_status='verified'
ORDER BY site.crawl_status DESC, target.canonical_name, site.site_id;
