BEGIN;

CREATE OR REPLACE VIEW jobpush.crawl_schedule_queue AS
SELECT
    target.priority_tier,
    target.priority_score,
    target.consolidation_key,
    target.canonical_name,
    site.site_id,
    site.source_type,
    site.site_url,
    site.scope_method,
    CASE target.priority_tier
        WHEN 'P0' THEN 24
        WHEN 'P1' THEN 72
        WHEN 'P2' THEN 168
    END AS recommended_interval_hours,
    site.last_crawled_at,
    site.last_success_at,
    site.next_crawl_at,
    COALESCE(site.next_crawl_at, now()) <= now() AS is_due,
    site.consecutive_failures,
    site.crawl_status
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier IN ('P0', 'P1', 'P2')
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.target_country_code = 'US'
  AND site.scope_method <> 'unknown'
  AND site.source_type IN (
      'apple_jobs', 'greenhouse', 'icims', 'oracle_cloud', 'workday',
      'lever', 'ashby', 'smartrecruiters', 'workable'
  );

WITH eligible AS (
    SELECT site.site_id
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P0', 'P1')
      AND site.verification_status = 'unverified'
      AND site.candidate_rank = 1
      AND site.source_type = 'workable'
      AND site.normalized_domain = 'apply.workable.com'
      AND NOT EXISTS (
          SELECT 1
          FROM jobpush.career_sites verified
          WHERE verified.consolidation_key = site.consolidation_key
            AND verified.verification_status = 'verified'
      )
)
UPDATE jobpush.career_sites site
SET verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    target_country_code = 'US',
    scope_method = 'local_filter',
    next_crawl_at = now(),
    crawl_interval_hours = CASE target.priority_tier
        WHEN 'P0' THEN 24
        WHEN 'P1' THEN 72
        WHEN 'P2' THEN 168
    END,
    reviewed_at = now(),
    reviewed_by = 'system:workable-apply-rank1-v1',
    review_notes = 'Auto-trusted rank-1 apply.workable.com candidate after Workable markdown adapter was added; jobs.workable.com remains excluded from this rule',
    updated_at = now()
FROM eligible
JOIN jobpush.crawl_targets target ON target.enabled
WHERE site.site_id = eligible.site_id
  AND target.consolidation_key = site.consolidation_key;

UPDATE jobpush.crawl_targets target
SET discovery_status = 'found',
    next_discovery_at = NULL,
    updated_at = now()
WHERE EXISTS (
    SELECT 1
    FROM jobpush.career_sites site
    WHERE site.consolidation_key = target.consolidation_key
      AND site.verification_status = 'verified'
      AND site.reviewed_by = 'system:workable-apply-rank1-v1'
);

UPDATE jobpush.career_sites site
SET crawl_interval_hours = CASE target.priority_tier
        WHEN 'P0' THEN 24
        WHEN 'P1' THEN 72
        WHEN 'P2' THEN 168
    END,
    next_crawl_at = COALESCE(site.next_crawl_at, now()),
    updated_at = now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.enabled
  AND target.priority_tier IN ('P0', 'P1', 'P2')
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.target_country_code = 'US'
  AND site.scope_method <> 'unknown'
  AND site.source_type = 'workable'
  AND site.normalized_domain = 'apply.workable.com';

COMMIT;
