\pset pager off

BEGIN;

UPDATE jobpush.career_sites site
SET site_url = 'https://www.amazon.jobs/en/search/?offset=0&result_limit=10&sort=recent&distanceType=Mi&radius=24km&latitude=38.89036&longitude=-77.03196&loc_group_id=&loc_query=United%20States&base_query=&city=&country=USA&region=&county=&query_options=&',
    source_type = 'amazon_jobs',
    source_key = 'amazon.jobs',
    site_kind = 'ats_feed',
    target_country_code = 'US',
    scope_method = 'server_filter',
    updated_at = now(),
    review_notes = concat_ws('; ', site.review_notes, 'Reclassified from generic_html by 099 Amazon Jobs adapter')
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.enabled
  AND target.priority_tier IN ('P0', 'P1')
  AND site.source_type = 'generic_html'
  AND site.verification_status = 'unverified'
  AND lower(site.normalized_domain) = 'amazon.jobs';

UPDATE jobpush.career_sites site
SET site_url = 'https://www.amazon.jobs/en/search/?offset=0&result_limit=10&sort=recent&distanceType=Mi&radius=24km&latitude=38.89036&longitude=-77.03196&loc_group_id=&loc_query=United%20States&base_query=&city=&country=USA&region=&county=&query_options=&',
    crawl_status = CASE WHEN crawl_status = 'failed' THEN 'pending' ELSE crawl_status END,
    next_crawl_at = CASE WHEN crawl_status = 'failed' THEN now() ELSE next_crawl_at END,
    updated_at = now(),
    review_notes = concat_ws('; ', site.review_notes, '099 normalized Amazon Jobs to verified US search URL')
WHERE site.source_type = 'amazon_jobs'
  AND lower(site.normalized_domain) = 'amazon.jobs';

-- Amazon subsidiaries share one US search endpoint. Keep one schedulable row
-- for now; duplicate rows remain reviewable but do not each crawl the same
-- 10k-job feed.
WITH ranked AS (
    SELECT site.site_id,
           row_number() OVER (
               ORDER BY target.priority_score DESC NULLS LAST, target.canonical_name, site.site_id
           ) AS rn
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P0', 'P1')
      AND site.source_type = 'amazon_jobs'
      AND lower(site.normalized_domain) = 'amazon.jobs'
)
UPDATE jobpush.career_sites site
SET crawl_enabled = ranked.rn = 1,
    next_crawl_at = CASE WHEN ranked.rn = 1 THEN now() ELSE NULL END,
    crawl_status = CASE WHEN ranked.rn = 1 THEN 'pending' ELSE 'pending' END,
    consecutive_failures = CASE WHEN ranked.rn = 1 THEN site.consecutive_failures ELSE 0 END,
    last_error = CASE WHEN ranked.rn = 1 THEN site.last_error ELSE NULL END,
    review_notes = concat_ws('; ', site.review_notes, CASE WHEN ranked.rn = 1 THEN '099 selected as Amazon shared crawl row' ELSE '099 disabled duplicate Amazon shared crawl row' END),
    updated_at = now()
FROM ranked
WHERE site.site_id = ranked.site_id
  AND site.verification_status = 'verified';

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
      'amazon_jobs', 'apple_jobs', 'greenhouse', 'icims', 'oracle_cloud',
      'workday', 'lever', 'ashby', 'smartrecruiters', 'workable',
      'jobvite', 'paylocity', 'rippling'
  );

COMMIT;

SELECT source_type, verification_status, crawl_enabled, count(*) AS sites
FROM jobpush.career_sites
WHERE normalized_domain = 'amazon.jobs'
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
