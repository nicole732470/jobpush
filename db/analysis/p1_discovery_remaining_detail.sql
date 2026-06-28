\pset pager off

\echo '=== P1 discovery remaining detail ==='
WITH site_rollup AS (
    SELECT
        site.consolidation_key,
        COUNT(*) FILTER (
            WHERE site.verification_status = 'unverified'
              AND site.source_type = 'generic_html'
        ) AS generic_unverified_sites,
        BOOL_OR(
            site.verification_status = 'unverified'
            AND site.source_type = 'generic_html'
            AND COALESCE(site.last_error, '') LIKE 'ats_url_guess_attempted%'
        ) AS has_generic_already_guessed,
        BOOL_OR(
            site.verification_status = 'unverified'
            AND site.source_type = 'generic_html'
            AND COALESCE(site.last_error, '') NOT LIKE 'ats_url_guess_attempted%'
        ) AS has_generic_not_yet_guessed,
        COUNT(*) FILTER (
            WHERE site.verification_status = 'unverified'
              AND site.source_type = 'generic_html'
              AND COALESCE(site.last_error, '') LIKE 'ats_url_guess_attempted%'
        ) AS generic_sites_already_guessed,
        COUNT(*) FILTER (
            WHERE site.verification_status = 'unverified'
              AND site.source_type = 'generic_html'
              AND COALESCE(site.last_error, '') NOT LIKE 'ats_url_guess_attempted%'
        ) AS generic_sites_not_yet_guessed,
        COUNT(*) FILTER (
            WHERE site.verification_status = 'unverified'
              AND site.source_type <> 'generic_html'
        ) AS structured_unverified_sites,
        COUNT(*) FILTER (
            WHERE site.verification_status = 'verified'
              AND site.crawl_enabled
        ) AS enabled_verified_sites,
        BOOL_OR(
            site.verification_status = 'verified'
            AND site.crawl_enabled
            AND site.last_success_at IS NOT NULL
        ) AS has_success
    FROM jobpush.career_sites site
    GROUP BY site.consolidation_key
), p1 AS (
    SELECT
        target.consolidation_key,
        target.discovery_status,
        COALESCE(site.generic_unverified_sites, 0) AS generic_unverified_sites,
        COALESCE(site.has_generic_already_guessed, false) AS has_generic_already_guessed,
        COALESCE(site.has_generic_not_yet_guessed, false) AS has_generic_not_yet_guessed,
        COALESCE(site.generic_sites_already_guessed, 0) AS generic_sites_already_guessed,
        COALESCE(site.generic_sites_not_yet_guessed, 0) AS generic_sites_not_yet_guessed,
        COALESCE(site.structured_unverified_sites, 0) AS structured_unverified_sites,
        COALESCE(site.enabled_verified_sites, 0) AS enabled_verified_sites,
        COALESCE(site.has_success, false) AS has_success
    FROM jobpush.crawl_targets target
    LEFT JOIN site_rollup site USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier = 'P1'
)
SELECT
    COUNT(*) AS p1_total,
    COUNT(*) FILTER (WHERE discovery_status = 'pending') AS p1_not_yet_tavily_searched,
    COUNT(*) FILTER (WHERE discovery_status = 'not_found') AS p1_tavily_searched_no_candidate,
    COUNT(*) FILTER (
        WHERE generic_unverified_sites > 0
          AND NOT has_success
          AND enabled_verified_sites = 0
    ) AS p1_generic_html_blocker_companies,
    COUNT(*) FILTER (
        WHERE has_generic_not_yet_guessed
          AND NOT has_success
          AND enabled_verified_sites = 0
    ) AS p1_companies_still_eligible_for_ats_guessing,
    COUNT(*) FILTER (
        WHERE has_generic_already_guessed
          AND NOT has_generic_not_yet_guessed
          AND NOT has_success
          AND enabled_verified_sites = 0
    ) AS p1_companies_generic_already_guessed_no_hit,
    SUM(generic_sites_not_yet_guessed) FILTER (
        WHERE NOT has_success
          AND enabled_verified_sites = 0
    ) AS generic_site_rows_still_eligible_for_ats_guessing,
    SUM(generic_sites_already_guessed) FILTER (
        WHERE NOT has_success
          AND enabled_verified_sites = 0
    ) AS generic_site_rows_already_guessed
FROM p1;

\echo '=== P1 generic blocker split ==='
WITH site_rollup AS (
    SELECT
        site.consolidation_key,
        BOOL_OR(
            site.verification_status = 'unverified'
            AND site.source_type = 'generic_html'
            AND COALESCE(site.last_error, '') LIKE 'ats_url_guess_attempted%'
        ) AS has_generic_already_guessed,
        BOOL_OR(
            site.verification_status = 'unverified'
            AND site.source_type = 'generic_html'
            AND COALESCE(site.last_error, '') NOT LIKE 'ats_url_guess_attempted%'
        ) AS has_generic_not_yet_guessed,
        COUNT(*) FILTER (
            WHERE site.verification_status = 'unverified'
              AND site.source_type = 'generic_html'
        ) AS generic_unverified_sites,
        COUNT(*) FILTER (
            WHERE site.verification_status = 'verified'
              AND site.crawl_enabled
        ) AS enabled_verified_sites,
        BOOL_OR(
            site.verification_status = 'verified'
            AND site.crawl_enabled
            AND site.last_success_at IS NOT NULL
        ) AS has_success
    FROM jobpush.career_sites site
    GROUP BY site.consolidation_key
), p1 AS (
    SELECT
        target.consolidation_key,
        COALESCE(site.generic_unverified_sites, 0) AS generic_unverified_sites,
        COALESCE(site.has_generic_already_guessed, false) AS has_generic_already_guessed,
        COALESCE(site.has_generic_not_yet_guessed, false) AS has_generic_not_yet_guessed,
        COALESCE(site.enabled_verified_sites, 0) AS enabled_verified_sites,
        COALESCE(site.has_success, false) AS has_success
    FROM jobpush.crawl_targets target
    LEFT JOIN site_rollup site USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier = 'P1'
)
SELECT
    CASE
        WHEN has_generic_not_yet_guessed THEN 'not_yet_ats_guessed'
        WHEN has_generic_already_guessed THEN 'already_ats_guessed_no_hit'
        ELSE 'other'
    END AS generic_blocker_state,
    COUNT(*) AS companies
FROM p1
WHERE generic_unverified_sites > 0
  AND NOT has_success
  AND enabled_verified_sites = 0
GROUP BY 1
ORDER BY 1;

\echo '=== Exact P1 companies matching run_guess_ats_sites selector ==='
SELECT
    COUNT(DISTINCT target.consolidation_key) AS p1_companies_exactly_eligible_for_next_ats_guess_run,
    COUNT(*) AS generic_site_rows_exactly_eligible_for_next_ats_guess_run
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier = 'P1'
  AND site.source_type = 'generic_html'
  AND site.verification_status = 'unverified'
  AND site.crawl_enabled = FALSE
  AND COALESCE(site.last_error, '') NOT LIKE 'ats_url_guess_attempted%'
  AND NOT EXISTS (
      SELECT 1
      FROM jobpush.career_sites structured
      WHERE structured.consolidation_key = site.consolidation_key
        AND structured.source_type IN ('greenhouse','lever','ashby','smartrecruiters')
        AND structured.verification_status IN ('verified', 'unverified')
  );
