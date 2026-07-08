\pset pager off

UPDATE jobpush.career_sites
SET crawl_status = 'pending',
    next_crawl_at = now(),
    updated_at = now()
WHERE source_type = 'applicantpro'
  AND verification_status = 'verified'
  AND crawl_enabled
  AND crawl_status = 'failed';

SELECT site.site_id, site.source_type, target.canonical_name, site.crawl_status, site.next_crawl_at, site.site_url
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.source_type = 'applicantpro'
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.next_crawl_at <= now()
ORDER BY target.priority_score DESC NULLS LAST, site.site_id
LIMIT 10;
