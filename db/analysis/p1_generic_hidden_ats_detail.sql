\pset pager off
WITH site_rollup AS (
    SELECT
        site.consolidation_key,
        bool_or(site.verification_status = 'verified' AND site.crawl_enabled) AS has_enabled_site,
        bool_or(site.verification_status = 'verified' AND site.crawl_enabled AND site.last_success_at IS NOT NULL) AS has_success
    FROM jobpush.career_sites site
    GROUP BY site.consolidation_key
), generic_sites AS (
    SELECT
        target.canonical_name,
        target.priority_score,
        site.site_id,
        site.site_url,
        lower(regexp_replace(coalesce(site.normalized_domain, split_part(regexp_replace(site.site_url, '^https?://', ''), '/', 1)), '^www\.', '')) AS host,
        site.candidate_score
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    LEFT JOIN site_rollup rollup USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier = 'P1'
      AND site.source_type = 'generic_html'
      AND site.verification_status = 'unverified'
      AND site.crawl_enabled = FALSE
      AND NOT coalesce(rollup.has_enabled_site, FALSE)
      AND NOT coalesce(rollup.has_success, FALSE)
)
SELECT
    CASE
        WHEN host LIKE '%greenhouse.io' THEN 'greenhouse'
        WHEN host LIKE '%ashbyhq.com' THEN 'ashby'
        WHEN host LIKE '%smartrecruiters.com' THEN 'smartrecruiters'
        WHEN host LIKE '%oraclecloud.com%' THEN 'oracle_cloud'
    END AS target_source_type,
    canonical_name,
    priority_score,
    site_id,
    site_url,
    candidate_score
FROM generic_sites
WHERE host LIKE '%greenhouse.io'
   OR host LIKE '%ashbyhq.com'
   OR host LIKE '%smartrecruiters.com'
   OR host LIKE '%oraclecloud.com%'
ORDER BY priority_score DESC NULLS LAST, candidate_score DESC NULLS LAST, canonical_name;
