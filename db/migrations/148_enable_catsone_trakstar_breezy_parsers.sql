BEGIN;

WITH eligible AS (
    SELECT DISTINCT ON (site.consolidation_key)
        site.site_id,
        target.priority_tier
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P0','P1','P2','P3')
      AND site.source_type = 'generic_html'
      AND site.normalized_domain LIKE '%.catsone.com'
      AND site.site_url ~* '/careers'
      AND site.verification_status = 'unverified'
      AND site.crawl_enabled = FALSE
      AND NOT EXISTS (
          SELECT 1 FROM jobpush.career_sites verified
          WHERE verified.consolidation_key = site.consolidation_key
            AND verified.verification_status = 'verified'
            AND verified.crawl_enabled
      )
    ORDER BY site.consolidation_key, site.candidate_score DESC NULLS LAST, site.candidate_rank NULLS LAST, site.site_id
)
UPDATE jobpush.career_sites site
SET source_type = 'catsone',
    source_key = site.normalized_domain,
    site_kind = 'ats_feed',
    verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    target_country_code = 'US',
    scope_method = 'local_filter',
    next_crawl_at = now(),
    crawl_interval_hours = CASE eligible.priority_tier WHEN 'P0' THEN 24 WHEN 'P1' THEN 72 WHEN 'P2' THEN 168 ELSE 336 END,
    reviewed_at = now(),
    reviewed_by = 'system:catsone-parser-v1',
    review_notes = concat_ws('; ', site.review_notes, 'Enabled CATS One board after 5-sample stable HTML validation'),
    updated_at = now()
FROM eligible
WHERE site.site_id = eligible.site_id;

WITH eligible AS (
    SELECT DISTINCT ON (site.consolidation_key)
        site.site_id,
        target.priority_tier,
        'https://' || site.normalized_domain || '/' AS board_url
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P0','P1','P2','P3')
      AND site.source_type = 'generic_html'
      AND site.normalized_domain LIKE '%.hire.trakstar.com'
      AND site.verification_status = 'unverified'
      AND site.crawl_enabled = FALSE
      AND NOT EXISTS (
          SELECT 1 FROM jobpush.career_sites verified
          WHERE verified.consolidation_key = site.consolidation_key
            AND verified.verification_status = 'verified'
            AND verified.crawl_enabled
      )
    ORDER BY site.consolidation_key, site.candidate_score DESC NULLS LAST, site.candidate_rank NULLS LAST, site.site_id
)
UPDATE jobpush.career_sites site
SET site_url = eligible.board_url,
    source_type = 'trakstar',
    source_key = site.normalized_domain,
    site_kind = 'ats_feed',
    verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    target_country_code = 'US',
    scope_method = 'local_filter',
    next_crawl_at = now(),
    crawl_interval_hours = CASE eligible.priority_tier WHEN 'P0' THEN 24 WHEN 'P1' THEN 72 WHEN 'P2' THEN 168 ELSE 336 END,
    reviewed_at = now(),
    reviewed_by = 'system:trakstar-parser-v1',
    review_notes = concat_ws('; ', site.review_notes, 'Enabled Trakstar Hire board after sample validation'),
    updated_at = now()
FROM eligible
WHERE site.site_id = eligible.site_id;

WITH eligible AS (
    SELECT DISTINCT ON (site.consolidation_key)
        site.site_id,
        target.priority_tier,
        'https://' || site.normalized_domain || '/' AS board_url
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P0','P1','P2','P3')
      AND site.source_type = 'generic_html'
      AND site.normalized_domain LIKE '%.breezy.hr'
      AND site.verification_status = 'unverified'
      AND site.crawl_enabled = FALSE
      AND NOT EXISTS (
          SELECT 1 FROM jobpush.career_sites verified
          WHERE verified.consolidation_key = site.consolidation_key
            AND verified.verification_status = 'verified'
            AND verified.crawl_enabled
      )
    ORDER BY site.consolidation_key, site.candidate_score DESC NULLS LAST, site.candidate_rank NULLS LAST, site.site_id
)
UPDATE jobpush.career_sites site
SET site_url = eligible.board_url,
    source_type = 'breezy',
    source_key = site.normalized_domain,
    site_kind = 'ats_feed',
    verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    target_country_code = 'US',
    scope_method = 'local_filter',
    next_crawl_at = now(),
    crawl_interval_hours = CASE eligible.priority_tier WHEN 'P0' THEN 24 WHEN 'P1' THEN 72 WHEN 'P2' THEN 168 ELSE 336 END,
    reviewed_at = now(),
    reviewed_by = 'system:breezy-parser-v1',
    review_notes = concat_ws('; ', site.review_notes, 'Enabled Breezy board after 3-sample stable HTML validation'),
    updated_at = now()
FROM eligible
WHERE site.site_id = eligible.site_id;

UPDATE jobpush.career_sites
SET verification_status = 'rejected',
    crawl_enabled = FALSE,
    crawl_status = 'paused',
    next_crawl_at = NULL,
    reviewed_at = now(),
    reviewed_by = 'system:platform-template-cleanup-v1',
    review_notes = concat_ws('; ', review_notes, 'Rejected non-board platform URL; send company back to rediscovery/review'),
    last_error = 'rejected_non_company_board_platform_url',
    updated_at = now()
WHERE source_type = 'generic_html'
  AND verification_status = 'unverified'
  AND crawl_enabled = FALSE
  AND (
      (normalized_domain = 'jobs.digitalhire.com' AND site_url ~* '/job-listing/opening/')
      OR (normalized_domain = 'recruit.hirebridge.com' AND site_url ~* '/v3/jobs/list\.aspx$')
  );

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
        WHEN 'P3' THEN 336
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
  AND target.priority_tier IN ('P0', 'P1', 'P2', 'P3')
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.target_country_code = 'US'
  AND site.scope_method <> 'unknown'
  AND site.source_type IN (
      'amazon_jobs', 'apple_jobs', 'breezy', 'catsone', 'cognizant_jobs',
      'dover', 'eightfold', 'generic_html', 'google_jobs', 'greenhouse',
      'icims', 'jobscore', 'oracle_cloud', 'trakstar', 'workday', 'lever',
      'ashby', 'smartrecruiters', 'workable', 'jobvite', 'paylocity',
      'rippling'
  );

COMMIT;

SELECT reviewed_by, source_type, verification_status, crawl_enabled, COUNT(*) AS sites
FROM jobpush.career_sites
WHERE reviewed_by IN (
    'system:catsone-parser-v1',
    'system:trakstar-parser-v1',
    'system:breezy-parser-v1',
    'system:platform-template-cleanup-v1'
)
GROUP BY 1, 2, 3, 4
ORDER BY 1, 2, 3, 4;
