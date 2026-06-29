\pset pager off
BEGIN;

WITH eligible AS (
    SELECT site.site_id, target.priority_tier
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier = 'P1'
      AND site.source_type = 'generic_html'
      AND site.verification_status = 'unverified'
      AND site.crawl_enabled = FALSE
      AND lower(site.normalized_domain) IN ('job-boards.eu.greenhouse.io', 'job-boards.greenhouse.io', 'boards.greenhouse.io')
      AND NOT EXISTS (
          SELECT 1
          FROM jobpush.career_sites verified
          WHERE verified.consolidation_key = site.consolidation_key
            AND verified.verification_status = 'verified'
            AND verified.crawl_enabled
      )
)
UPDATE jobpush.career_sites site
SET source_type = 'greenhouse',
    source_key = split_part(regexp_replace(site.site_url, '^https?://[^/]+/', ''), '/', 1),
    site_kind = 'ats_feed',
    verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    target_country_code = 'US',
    scope_method = 'local_filter',
    next_crawl_at = now(),
    crawl_interval_hours = 72,
    reviewed_at = now(),
    reviewed_by = 'system:p1-hidden-greenhouse-v1',
    review_notes = concat_ws('; ', site.review_notes, 'Promoted hidden Greenhouse generic_html by ops/promote_p1_hidden_greenhouse_sites'),
    updated_at = now()
FROM eligible
WHERE site.site_id = eligible.site_id;

UPDATE jobpush.crawl_targets target
SET discovery_status = 'found',
    next_discovery_at = NULL,
    updated_at = now()
WHERE EXISTS (
    SELECT 1
    FROM jobpush.career_sites site
    WHERE site.consolidation_key = target.consolidation_key
      AND site.reviewed_by = 'system:p1-hidden-greenhouse-v1'
      AND site.verification_status = 'verified'
      AND site.crawl_enabled
);

COMMIT;

SELECT target.canonical_name, site.site_id, site.source_type, site.source_key, site.crawl_status, site.next_crawl_at
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.reviewed_by = 'system:p1-hidden-greenhouse-v1'
ORDER BY target.priority_score DESC NULLS LAST, target.canonical_name;
