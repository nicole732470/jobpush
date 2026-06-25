\pset pager off

\echo '=== P1 funnel by operational state ==='
WITH site_rollup AS (
    SELECT
        consolidation_key,
        COUNT(*) FILTER (WHERE verification_status IN ('verified', 'unverified')) AS retained_site_candidates,
        COUNT(*) FILTER (WHERE verification_status = 'verified') AS verified_sites,
        COUNT(*) FILTER (WHERE verification_status = 'verified' AND crawl_enabled) AS enabled_sites,
        BOOL_OR(verification_status = 'verified' AND crawl_enabled AND last_success_at IS NOT NULL) AS has_success,
        BOOL_OR(verification_status = 'verified' AND crawl_enabled AND last_crawled_at IS NOT NULL) AS has_attempt,
        BOOL_OR(verification_status = 'verified' AND crawl_enabled AND crawl_status = 'failed') AS has_current_failure,
        COUNT(*) FILTER (WHERE verification_status = 'unverified' AND source_type = 'generic_html') AS generic_unverified_candidates,
        COUNT(*) FILTER (WHERE verification_status = 'unverified' AND source_type <> 'generic_html') AS structured_unverified_candidates
    FROM jobpush.career_sites
    GROUP BY consolidation_key
),
p1 AS (
    SELECT
        target.consolidation_key,
        target.canonical_name,
        target.discovery_status,
        COALESCE(site.retained_site_candidates, 0) AS retained_site_candidates,
        COALESCE(site.verified_sites, 0) AS verified_sites,
        COALESCE(site.enabled_sites, 0) AS enabled_sites,
        COALESCE(site.has_success, false) AS has_success,
        COALESCE(site.has_attempt, false) AS has_attempt,
        COALESCE(site.has_current_failure, false) AS has_current_failure,
        COALESCE(site.generic_unverified_candidates, 0) AS generic_unverified_candidates,
        COALESCE(site.structured_unverified_candidates, 0) AS structured_unverified_candidates
    FROM jobpush.crawl_targets target
    LEFT JOIN site_rollup site USING (consolidation_key)
    WHERE target.enabled AND target.priority_tier = 'P1'
),
classified AS (
    SELECT *,
        CASE
            WHEN has_success THEN '01_successfully_crawled'
            WHEN enabled_sites > 0 AND has_attempt AND has_current_failure THEN '02_attempted_but_currently_failed'
            WHEN enabled_sites > 0 AND has_attempt THEN '03_attempted_no_success_no_current_failure'
            WHEN enabled_sites > 0 THEN '04_enabled_due_not_yet_crawled'
            WHEN structured_unverified_candidates > 0 THEN '05_structured_candidate_not_enabled'
            WHEN generic_unverified_candidates > 0 THEN '06_generic_html_candidate_needs_site_resolution'
            WHEN retained_site_candidates > 0 THEN '07_other_candidate_needs_review'
            WHEN discovery_status = 'not_found' THEN '08_tavily_searched_no_candidate'
            WHEN discovery_status = 'pending' THEN '09_not_searched_yet'
            ELSE '10_other'
        END AS blocker
    FROM p1
)
SELECT
    blocker,
    COUNT(*) AS companies,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_p1
FROM classified
GROUP BY blocker
ORDER BY blocker;

\echo '=== P1 failure breakdown by adapter and error ==='
WITH latest_failed AS (
    SELECT DISTINCT ON (site.consolidation_key)
        target.priority_tier,
        target.consolidation_key,
        target.canonical_name,
        site.site_id,
        site.source_type,
        site.site_url,
        site.consecutive_failures,
        site.last_error,
        run.error_code,
        run.error_message,
        run.started_at
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    LEFT JOIN jobpush.crawl_runs run
      ON run.site_id = site.site_id AND run.status = 'failed'
    WHERE target.enabled
      AND target.priority_tier = 'P1'
      AND site.verification_status = 'verified'
      AND site.crawl_enabled
      AND site.crawl_status = 'failed'
    ORDER BY site.consolidation_key, run.started_at DESC NULLS LAST, site.site_id
)
SELECT
    source_type,
    CASE
        WHEN COALESCE(last_error, error_message, '') ILIKE '%404%' THEN 'http_404_wrong_or_stale_ats_slug'
        WHEN COALESCE(last_error, error_message, '') ILIKE '%422%' THEN 'http_422_workday_payload_or_endpoint'
        WHEN COALESCE(last_error, error_message, '') ILIKE '%timeout%' THEN 'timeout'
        WHEN COALESCE(last_error, error_message, '') = '' THEN 'unknown_no_error_text'
        ELSE 'other'
    END AS failure_reason,
    COUNT(*) AS companies
FROM latest_failed
GROUP BY 1, 2
ORDER BY companies DESC, source_type, failure_reason;

\echo '=== P1 failed companies detail ==='
SELECT
    source_type,
    canonical_name,
    consecutive_failures,
    left(COALESCE(last_error, error_message, ''), 180) AS error_text,
    site_url
FROM (
    SELECT DISTINCT ON (site.consolidation_key)
        target.canonical_name,
        site.source_type,
        site.site_url,
        site.consecutive_failures,
        site.last_error,
        run.error_message,
        run.started_at
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    LEFT JOIN jobpush.crawl_runs run
      ON run.site_id = site.site_id AND run.status = 'failed'
    WHERE target.enabled
      AND target.priority_tier = 'P1'
      AND site.verification_status = 'verified'
      AND site.crawl_enabled
      AND site.crawl_status = 'failed'
    ORDER BY site.consolidation_key, run.started_at DESC NULLS LAST, site.site_id
) failed
ORDER BY source_type, canonical_name;

\echo '=== P1 pending/not-found examples ==='
SELECT discovery_status, canonical_name, priority_score
FROM jobpush.crawl_targets
WHERE enabled AND priority_tier = 'P1'
  AND discovery_status IN ('pending', 'not_found')
ORDER BY discovery_status, priority_score DESC, canonical_name
LIMIT 50;
