\pset pager off

\echo '=== P1 failed enabled sites detail ==='
SELECT
    target.canonical_name,
    target.priority_score,
    site.source_type,
    site.site_url,
    CASE
        WHEN coalesce(site.last_error, '') ILIKE '%404%' THEN 'rediscover ATS slug'
        WHEN coalesce(site.last_error, '') ILIKE '%timeout%' OR coalesce(site.last_error, '') ILIKE '%timed out%' THEN 'retry after Workday retry patch'
        WHEN coalesce(site.last_error, '') ILIKE '%422%' THEN 'inspect Workday site path / payload'
        ELSE 'inspect adapter log'
    END AS next_action,
    left(coalesce(site.last_error, ''), 220) AS last_error
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier = 'P1'
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.crawl_status = 'failed'
ORDER BY target.priority_score DESC NULLS LAST, target.canonical_name;

\echo '=== P1 top 1000 unresolved companies for export/review ==='
WITH ranked AS (
    SELECT target.*,
           row_number() OVER (ORDER BY target.priority_score DESC NULLS LAST, target.canonical_name) AS p1_rank
    FROM jobpush.crawl_targets target
    WHERE target.enabled AND target.priority_tier = 'P1'
), site_rollup AS (
    SELECT
        site.consolidation_key,
        bool_or(site.verification_status = 'verified' AND site.crawl_enabled AND site.last_success_at IS NOT NULL) AS has_success,
        bool_or(site.verification_status = 'verified' AND site.crawl_enabled AND site.crawl_status = 'failed') AS has_failed,
        count(*) FILTER (WHERE site.verification_status = 'unverified' AND site.source_type = 'generic_html') AS generic_candidates,
        count(*) FILTER (WHERE site.verification_status = 'unverified' AND site.source_type <> 'generic_html') AS structured_candidates,
        min(site.site_url) FILTER (WHERE site.verification_status = 'unverified' AND site.candidate_rank = 1) AS best_candidate_url,
        string_agg(DISTINCT site.source_type, ', ' ORDER BY site.source_type) AS source_types
    FROM jobpush.career_sites site
    GROUP BY site.consolidation_key
)
SELECT ranked.p1_rank,
       ranked.canonical_name,
       ranked.priority_score,
       CASE
           WHEN coalesce(site.has_failed, false) THEN 'failed_enabled_site'
           WHEN coalesce(site.structured_candidates, 0) > 0 THEN 'structured_candidate_not_enabled'
           WHEN coalesce(site.generic_candidates, 0) > 0 THEN 'generic_html_needs_resolution'
           ELSE 'no_usable_site'
       END AS blocker,
       coalesce(site.source_types, '') AS source_types,
       site.best_candidate_url
FROM ranked
LEFT JOIN site_rollup site USING (consolidation_key)
WHERE ranked.p1_rank <= 1000
  AND NOT coalesce(site.has_success, false)
ORDER BY ranked.p1_rank
LIMIT 300;
