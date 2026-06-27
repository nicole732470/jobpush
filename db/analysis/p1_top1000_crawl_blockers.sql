\pset pager off

\echo '=== P1 top 1000 crawl-state distribution ==='
WITH ranked AS (
    SELECT target.*,
           row_number() OVER (
               ORDER BY target.priority_score DESC NULLS LAST, target.canonical_name
           ) AS priority_rank
    FROM jobpush.crawl_targets target
    WHERE target.enabled
      AND target.priority_tier = 'P1'
), site_rollup AS (
    SELECT
        site.consolidation_key,
        bool_or(site.verification_status = 'verified' AND site.crawl_enabled) AS has_enabled_site,
        bool_or(site.verification_status = 'verified' AND site.crawl_enabled AND site.last_crawled_at IS NOT NULL) AS has_attempt,
        bool_or(site.verification_status = 'verified' AND site.crawl_enabled AND site.last_success_at IS NOT NULL) AS has_success,
        bool_or(site.verification_status = 'verified' AND site.crawl_enabled AND site.crawl_status = 'failed') AS has_failed,
        count(*) FILTER (WHERE site.verification_status = 'unverified') AS unverified_candidates,
        count(*) FILTER (WHERE site.verification_status = 'unverified' AND site.source_type = 'generic_html') AS generic_candidates,
        count(*) FILTER (WHERE site.verification_status = 'unverified' AND site.source_type <> 'generic_html') AS structured_candidates,
        string_agg(DISTINCT site.source_type, ', ' ORDER BY site.source_type) FILTER (WHERE site.verification_status = 'unverified') AS unverified_source_types,
        string_agg(DISTINCT site.source_type, ', ' ORDER BY site.source_type) FILTER (WHERE site.verification_status = 'verified') AS verified_source_types
    FROM jobpush.career_sites site
    GROUP BY site.consolidation_key
), due AS (
    SELECT consolidation_key, count(*) FILTER (WHERE is_due) AS due_sites
    FROM jobpush.crawl_schedule_queue
    GROUP BY consolidation_key
), classified AS (
    SELECT
        ranked.priority_rank,
        ranked.consolidation_key,
        ranked.canonical_name,
        ranked.priority_score,
        ranked.discovery_status,
        COALESCE(site.unverified_source_types, '') AS unverified_source_types,
        COALESCE(site.verified_source_types, '') AS verified_source_types,
        CASE
            WHEN COALESCE(site.has_success, FALSE) THEN '01_successfully_crawled'
            WHEN COALESCE(site.has_failed, FALSE) THEN '02_adapter_or_site_failed'
            WHEN COALESCE(due.due_sites, 0) > 0 THEN '03_enabled_waiting_for_scheduler'
            WHEN COALESCE(site.has_enabled_site, FALSE) THEN '04_enabled_not_due_yet'
            WHEN COALESCE(site.structured_candidates, 0) > 0 THEN '05_structured_candidate_not_enabled'
            WHEN COALESCE(site.generic_candidates, 0) > 0 THEN '06_generic_html_needs_resolution'
            WHEN ranked.discovery_status = 'pending' THEN '07_not_searched_yet'
            ELSE '08_searched_no_usable_candidate'
        END AS crawl_state
    FROM ranked
    LEFT JOIN site_rollup site USING (consolidation_key)
    LEFT JOIN due USING (consolidation_key)
    WHERE ranked.priority_rank <= 1000
)
SELECT crawl_state,
       count(*) AS companies,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct,
       min(priority_rank) AS best_rank,
       max(priority_rank) AS worst_rank
FROM classified
GROUP BY crawl_state
ORDER BY crawl_state;

\echo '=== P1 top 1000 blockers by candidate source ==='
WITH ranked AS (
    SELECT target.*,
           row_number() OVER (
               ORDER BY target.priority_score DESC NULLS LAST, target.canonical_name
           ) AS priority_rank
    FROM jobpush.crawl_targets target
    WHERE target.enabled
      AND target.priority_tier = 'P1'
), site_rollup AS (
    SELECT
        site.consolidation_key,
        bool_or(site.verification_status = 'verified' AND site.crawl_enabled) AS has_enabled_site,
        bool_or(site.verification_status = 'verified' AND site.crawl_enabled AND site.last_success_at IS NOT NULL) AS has_success,
        bool_or(site.verification_status = 'verified' AND site.crawl_enabled AND site.crawl_status = 'failed') AS has_failed,
        count(*) FILTER (WHERE site.verification_status = 'unverified' AND site.source_type = 'generic_html') AS generic_candidates,
        count(*) FILTER (WHERE site.verification_status = 'unverified' AND site.source_type <> 'generic_html') AS structured_candidates,
        string_agg(DISTINCT site.source_type, ', ' ORDER BY site.source_type) FILTER (WHERE site.verification_status = 'unverified') AS unverified_source_types
    FROM jobpush.career_sites site
    GROUP BY site.consolidation_key
), classified AS (
    SELECT
        ranked.priority_rank,
        ranked.canonical_name,
        ranked.priority_score,
        CASE
            WHEN COALESCE(site.has_success, FALSE) THEN 'successfully_crawled'
            WHEN COALESCE(site.has_failed, FALSE) THEN 'adapter_or_site_failed'
            WHEN COALESCE(site.has_enabled_site, FALSE) THEN 'enabled_but_not_success'
            WHEN COALESCE(site.structured_candidates, 0) > 0 THEN 'structured_candidate_not_enabled'
            WHEN COALESCE(site.generic_candidates, 0) > 0 THEN 'generic_html_needs_resolution'
            WHEN ranked.discovery_status = 'pending' THEN 'not_searched_yet'
            ELSE 'searched_no_usable_candidate'
        END AS crawl_state,
        COALESCE(NULLIF(site.unverified_source_types, ''), '(none)') AS candidate_sources
    FROM ranked
    LEFT JOIN site_rollup site USING (consolidation_key)
    WHERE ranked.priority_rank <= 1000
)
SELECT crawl_state, candidate_sources,
       count(*) AS companies,
       string_agg(canonical_name, ', ' ORDER BY priority_rank) AS example_companies
FROM classified
WHERE crawl_state <> 'successfully_crawled'
GROUP BY crawl_state, candidate_sources
ORDER BY companies DESC, crawl_state, candidate_sources
LIMIT 25;

\echo '=== P1 top 1000 highest-ranked companies not successfully crawled ==='
WITH ranked AS (
    SELECT target.*,
           row_number() OVER (
               ORDER BY target.priority_score DESC NULLS LAST, target.canonical_name
           ) AS priority_rank
    FROM jobpush.crawl_targets target
    WHERE target.enabled
      AND target.priority_tier = 'P1'
), site_rollup AS (
    SELECT
        site.consolidation_key,
        bool_or(site.verification_status = 'verified' AND site.crawl_enabled AND site.last_success_at IS NOT NULL) AS has_success,
        bool_or(site.verification_status = 'verified' AND site.crawl_enabled AND site.crawl_status = 'failed') AS has_failed,
        count(*) FILTER (WHERE site.verification_status = 'unverified' AND site.source_type = 'generic_html') AS generic_candidates,
        count(*) FILTER (WHERE site.verification_status = 'unverified' AND site.source_type <> 'generic_html') AS structured_candidates,
        string_agg(DISTINCT site.source_type, ', ' ORDER BY site.source_type) AS source_types,
        min(site.site_url) FILTER (WHERE site.candidate_rank = 1) AS candidate_1_url
    FROM jobpush.career_sites site
    GROUP BY site.consolidation_key
)
SELECT ranked.priority_rank, ranked.canonical_name, ranked.priority_score,
       ranked.discovery_status,
       CASE
           WHEN COALESCE(site.has_failed, FALSE) THEN 'adapter_or_site_failed'
           WHEN COALESCE(site.structured_candidates, 0) > 0 THEN 'structured_candidate_not_enabled'
           WHEN COALESCE(site.generic_candidates, 0) > 0 THEN 'generic_html_needs_resolution'
           WHEN ranked.discovery_status = 'pending' THEN 'not_searched_yet'
           ELSE 'searched_no_usable_candidate'
       END AS likely_blocker,
       COALESCE(site.source_types, '') AS source_types,
       site.candidate_1_url
FROM ranked
LEFT JOIN site_rollup site USING (consolidation_key)
WHERE ranked.priority_rank <= 1000
  AND NOT COALESCE(site.has_success, FALSE)
ORDER BY ranked.priority_rank
LIMIT 80;
