\pset pager off

UPDATE jobpush.career_sites site
SET crawl_status = 'pending',
    next_crawl_at = now(),
    updated_at = now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.enabled
  AND target.priority_tier IN ('P0', 'P1')
  AND site.source_type = 'amazon_jobs'
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.crawl_status = 'failed';

SELECT target.priority_tier, site.source_type, site.crawl_status, count(*) AS sites
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.source_type = 'amazon_jobs'
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
