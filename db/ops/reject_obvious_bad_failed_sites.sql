\pset pager off
UPDATE jobpush.career_sites site
SET verification_status='rejected',
    crawl_enabled=FALSE,
    crawl_status='paused',
    review_notes=concat_ws('; ', review_notes, 'Rejected obvious bad failed URL by ops/reject_obvious_bad_failed_sites'),
    updated_at=now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key=site.consolidation_key
  AND target.enabled
  AND target.priority_tier IN ('P0','P1')
  AND site.verification_status='verified'
  AND site.crawl_enabled
  AND site.crawl_status='failed'
  AND (
    (site.source_type='eightfold' AND (site.site_url ILIKE '%eightfold.ai/privacy-policy%' OR site.site_url ILIKE '%vs-errors.eightfold.ai%'))
    OR (site.source_type='workable' AND site.site_url='https://jobs.workable.com/company')
    OR (site.source_type='workday' AND (site.site_url LIKE '%"}}%' OR site.site_url ~ '^https://[^/]+/$'))
  );

SELECT site.source_type, site.verification_status, site.crawl_enabled, site.crawl_status, count(*)
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier IN ('P0','P1')
  AND site.source_type IN ('eightfold','workable','workday')
GROUP BY 1,2,3,4
ORDER BY 1,2,3,4;
