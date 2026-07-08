\pset pager off

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
      AND site.normalized_domain LIKE '%.applicantpro.com'
      AND site.verification_status = 'unverified'
      AND site.crawl_enabled = FALSE
      AND NOT EXISTS (
          SELECT 1
          FROM jobpush.career_sites verified
          WHERE verified.consolidation_key = site.consolidation_key
            AND verified.verification_status = 'verified'
            AND verified.crawl_enabled
      )
    ORDER BY site.consolidation_key,
             site.candidate_score DESC NULLS LAST,
             site.candidate_rank NULLS LAST,
             site.site_id
)
UPDATE jobpush.career_sites site
SET source_type = 'applicantpro',
    source_key = lower(split_part(site.normalized_domain, '.applicantpro.com', 1)),
    site_kind = 'ats_feed',
    verification_status = 'verified',
    crawl_enabled = TRUE,
    crawl_status = 'pending',
    target_country_code = 'US',
    scope_method = 'local_filter',
    next_crawl_at = now(),
    crawl_interval_hours = CASE eligible.priority_tier
        WHEN 'P0' THEN 24 WHEN 'P1' THEN 72 WHEN 'P2' THEN 168 ELSE 336 END,
    reviewed_at = now(),
    reviewed_by = 'system:applicantpro-parser-v1',
    review_notes = concat_ws('; ', site.review_notes, 'Enabled ApplicantPro board after JSON endpoint validation'),
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
      'amazon_jobs', 'apple_jobs', 'cognizant_jobs', 'eightfold', 'generic_html',
      'google_jobs', 'greenhouse', 'icims', 'oracle_cloud', 'workday', 'lever',
      'ashby', 'smartrecruiters', 'workable', 'jobvite', 'paylocity', 'rippling',
      'ultipro', 'jobscore', 'applicantpro', 'dover', 'catsone', 'trakstar',
      'breezy', 'applytojob'
  );

COMMIT;

SELECT target.priority_tier, site.source_type, site.verification_status, site.crawl_enabled,
       site.crawl_status, count(*) AS sites
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.reviewed_by = 'system:applicantpro-parser-v1'
GROUP BY 1, 2, 3, 4, 5
ORDER BY 1, 2, 3, 4, 5;
