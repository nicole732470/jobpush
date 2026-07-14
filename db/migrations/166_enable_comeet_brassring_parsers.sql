-- Enable Comeet + Brassring adapters in the schedulable crawl queue.
-- Comeet: requires hosted board /jobs/{slug}/{COMPANY.UID}
-- Brassring: requires partnerid+siteid tenant board URL

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
      'breezy', 'applytojob', 'phenom', 'comeet', 'brassring'
  );

COMMIT;

SELECT 'comeet' AS source_type, count(*) AS schedulable
FROM jobpush.crawl_schedule_queue WHERE source_type = 'comeet'
UNION ALL
SELECT 'brassring', count(*)
FROM jobpush.crawl_schedule_queue WHERE source_type = 'brassring';
