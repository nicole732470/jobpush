\pset pager off

BEGIN;

-- ponytail: repeated structured ATS timeouts are not due-crawl candidates.
UPDATE jobpush.career_sites site
SET crawl_enabled = FALSE,
    crawl_status = 'paused',
    verification_status = CASE
        WHEN site.reviewed_by LIKE 'system:%' THEN 'unverified'
        ELSE site.verification_status
    END,
    review_notes = concat_ws(
        '; ',
        site.review_notes,
        'Quarantined chronic structured ATS timeout (ops/quarantine_chronic_structured_timeouts)'
    ),
    updated_at = now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.enabled
  AND target.priority_tier IN ('P1', 'P2', 'P3')
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.crawl_status = 'failed'
  AND site.source_type IN ('ashby', 'greenhouse', 'lever', 'smartrecruiters', 'rippling')
  AND site.consecutive_failures >= 4
  AND (
      coalesce(site.last_error, '') ILIKE '%timeout%'
      OR coalesce(site.last_error, '') ILIKE '%timed out%'
      OR coalesce(site.last_error, '') ILIKE '%urlopen%'
  );

COMMIT;

SELECT site.source_type, site.crawl_status, site.verification_status, site.crawl_enabled, count(*) AS sites
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier = 'P2'
  AND site.review_notes ILIKE '%quarantine_chronic_structured_timeouts%'
GROUP BY 1, 2, 3, 4
ORDER BY 1, 2, 3, 4;
