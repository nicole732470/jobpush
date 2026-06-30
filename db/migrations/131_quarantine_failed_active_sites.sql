BEGIN;

-- These sites were auto-enabled by broad pilots, then repeatedly failed.
-- Keep the rows for review/history, but remove them from the active scheduler.
UPDATE jobpush.career_sites site
SET
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    verification_status = CASE
        WHEN site.reviewed_by LIKE 'system:%' THEN 'unverified'
        ELSE site.verification_status
    END,
    last_error = concat_ws(
        '; ',
        nullif(site.last_error, ''),
        'quarantined_failed_active_site_2026_06_30'
    ),
    updated_at = now()
WHERE site.site_id IN (
    122,   -- TWG Global generic_html timeout
    158,   -- AiRo generic_html timeout
    1248,  -- Ericsson generic_html timeout
    12757, -- Corva bad Rippling slug; site 12756 already succeeds
    12846, -- GAF Workday blocked
    13147, -- Lexyta wrong/stale Lever slug
    16128, -- AWS Security Assurances Amazon timeout/detail URL
    15655, -- Augment stale Ashby slug
    18132  -- Biostate stale Ashby slug
);

-- Quarantine all currently failed P2 stale structured URLs of the same kind
-- without naming every row; these need rediscovery, not retry spam.
UPDATE jobpush.career_sites site
SET
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    verification_status = CASE
        WHEN site.reviewed_by LIKE 'system:%' THEN 'unverified'
        ELSE site.verification_status
    END,
    last_error = concat_ws(
        '; ',
        nullif(site.last_error, ''),
        'quarantined_failed_active_site_2026_06_30'
    ),
    updated_at = now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.enabled
  AND target.priority_tier = 'P2'
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.crawl_status = 'failed'
  AND site.source_type IN ('greenhouse', 'ashby', 'workday')
  AND (
      coalesce(site.last_error, '') ILIKE '%404%'
      OR coalesce(site.last_error, '') ILIKE '%HTTP Error 404%'
      OR coalesce(site.last_error, '') ILIKE '%wrong_or_stale%'
  );

COMMIT;

\pset pager off

SELECT
    target.priority_tier,
    site.source_type,
    site.crawl_status,
    site.verification_status,
    count(*) AS quarantined_sites
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.last_error LIKE '%quarantined_failed_active_site_2026_06_30%'
GROUP BY 1, 2, 3, 4
ORDER BY 1, 2, 3, 4;
