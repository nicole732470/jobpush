BEGIN;

WITH candidates AS (
    SELECT
        site.site_id,
        site.consolidation_key,
        target.priority_tier,
        site.candidate_score,
        site.candidate_rank,
        'https://' || site.normalized_domain || '/apply' AS board_url,
        site.site_url = 'https://' || site.normalized_domain || '/apply' AS already_canonical
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P0','P1','P2','P3')
      AND site.source_type = 'generic_html'
      AND site.normalized_domain LIKE '%.applytojob.com'
      AND site.normalized_domain <> 'applytojob.com'
      AND site.verification_status = 'unverified'
      AND site.crawl_enabled = FALSE
      AND NOT EXISTS (
          SELECT 1 FROM jobpush.career_sites verified
          WHERE verified.consolidation_key = site.consolidation_key
            AND verified.verification_status = 'verified'
            AND verified.crawl_enabled
      )
), eligible AS (
    SELECT DISTINCT ON (consolidation_key, board_url)
        site_id,
        priority_tier,
        board_url
    FROM candidates
    ORDER BY consolidation_key,
             board_url,
             already_canonical DESC,
             candidate_score DESC NULLS LAST,
             candidate_rank NULLS LAST,
             site_id
)
UPDATE jobpush.career_sites site
SET site_url = eligible.board_url,
    source_type = 'applytojob',
    source_key = site.normalized_domain,
    site_kind = 'ats_feed',
    verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    target_country_code = 'US',
    scope_method = 'verified_us_only',
    next_crawl_at = now(),
    crawl_interval_hours = CASE eligible.priority_tier
        WHEN 'P0' THEN 24 WHEN 'P1' THEN 72 WHEN 'P2' THEN 168 ELSE 336 END,
    reviewed_at = now(),
    reviewed_by = 'system:applytojob-parser-v1',
    review_notes = concat_ws('; ', site.review_notes, 'Enabled ApplyToJob/JazzHR board after sample validation; parser keeps US-local titles and relies on title classifier/YAML for noise'),
    updated_at = now()
FROM eligible
WHERE site.site_id = eligible.site_id;

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
      'amazon_jobs', 'apple_jobs', 'applytojob', 'breezy', 'catsone',
      'cognizant_jobs', 'dover', 'eightfold', 'generic_html', 'google_jobs',
      'greenhouse', 'icims', 'jobscore', 'oracle_cloud', 'trakstar',
      'workday', 'lever', 'ashby', 'smartrecruiters', 'workable', 'jobvite',
      'paylocity', 'rippling'
  );

COMMIT;

SELECT reviewed_by, source_type, verification_status, crawl_enabled, COUNT(*) AS sites
FROM jobpush.career_sites
WHERE reviewed_by = 'system:applytojob-parser-v1'
GROUP BY 1, 2, 3, 4
ORDER BY 1, 2, 3, 4;
