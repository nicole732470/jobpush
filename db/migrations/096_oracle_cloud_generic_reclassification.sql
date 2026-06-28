\pset pager off

BEGIN;

-- Tavily sometimes returned Oracle Recruiting Cloud career URLs before the
-- classifier knew how to recognize them. They were stored as generic_html,
-- which blocked otherwise supported Oracle adapter crawling.
UPDATE jobpush.career_sites site
SET
    source_type = 'oracle_cloud',
    source_key = lower(regexp_replace(coalesce(site.normalized_domain, split_part(regexp_replace(site.site_url, '^https?://', ''), '/', 1)), '^www\.', '')),
    site_kind = 'ats_feed',
    target_country_code = 'US',
    scope_method = 'server_filter',
    crawl_status = CASE
        WHEN site.crawl_status = 'skipped' THEN 'pending'
        ELSE site.crawl_status
    END,
    last_error = CASE
        WHEN coalesce(site.last_error, '') LIKE 'ats_url_guess_attempted%' THEN site.last_error
        WHEN coalesce(site.last_error, '') LIKE 'generic_ats_resolution_attempted%' THEN site.last_error
        ELSE site.last_error
    END,
    updated_at = now()
WHERE site.source_type = 'generic_html'
  AND lower(coalesce(site.normalized_domain, split_part(regexp_replace(site.site_url, '^https?://', ''), '/', 1))) LIKE '%oraclecloud.com'
  AND site.site_url ILIKE '%/hcmUI/CandidateExperience/%/sites/%/jobs%';

COMMIT;

SELECT source_type, verification_status, crawl_enabled, count(*) AS sites
FROM jobpush.career_sites
WHERE lower(coalesce(normalized_domain, split_part(regexp_replace(site_url, '^https?://', ''), '/', 1))) LIKE '%oraclecloud.com'
GROUP BY 1, 2, 3
ORDER BY 1, 2, 3;
