\pset pager off

\echo '=== P2 full crawl-state distribution ==='
WITH site_rollup AS (
    SELECT
        site.consolidation_key,
        bool_or(site.verification_status = 'verified' AND site.crawl_enabled) AS has_enabled_site,
        bool_or(site.verification_status = 'verified' AND site.crawl_enabled AND site.last_success_at IS NOT NULL) AS has_success,
        bool_or(site.verification_status = 'verified' AND site.crawl_enabled AND site.crawl_status = 'failed') AS has_failed,
        count(*) FILTER (WHERE site.verification_status = 'unverified') AS unverified_candidates,
        count(*) FILTER (WHERE site.verification_status = 'unverified' AND site.source_type = 'generic_html') AS generic_candidates,
        count(*) FILTER (WHERE site.verification_status = 'unverified' AND site.source_type <> 'generic_html') AS structured_candidates,
        string_agg(DISTINCT site.source_type, ', ' ORDER BY site.source_type)
            FILTER (WHERE site.verification_status = 'unverified' AND site.source_type <> 'generic_html') AS unverified_structured_types
    FROM jobpush.career_sites site
    GROUP BY site.consolidation_key
), due AS (
    SELECT consolidation_key, count(*) FILTER (WHERE is_due) AS due_sites
    FROM jobpush.crawl_schedule_queue
    GROUP BY consolidation_key
), classified AS (
    SELECT
        target.consolidation_key,
        target.canonical_name,
        target.priority_score,
        target.discovery_status,
        CASE
            WHEN COALESCE(site.has_success, FALSE) THEN '01_successfully_crawled'
            WHEN COALESCE(site.has_failed, FALSE) THEN '02_adapter_or_site_failed'
            WHEN COALESCE(due.due_sites, 0) > 0 THEN '03_enabled_waiting_for_scheduler'
            WHEN COALESCE(site.has_enabled_site, FALSE) THEN '04_enabled_not_due_yet'
            WHEN COALESCE(site.structured_candidates, 0) > 0 THEN '05_structured_candidate_needs_autotrust'
            WHEN COALESCE(site.generic_candidates, 0) > 0 THEN '06_generic_html_needs_resolution'
            WHEN target.discovery_status = 'pending' AND target.last_discovery_at IS NULL THEN '07_not_searched_yet'
            ELSE '08_searched_no_usable_candidate'
        END AS crawl_state,
        site.unverified_structured_types
    FROM jobpush.crawl_targets target
    LEFT JOIN site_rollup site USING (consolidation_key)
    LEFT JOIN due USING (consolidation_key)
    WHERE target.enabled AND target.priority_tier = 'P2'
)
SELECT crawl_state,
       count(*) AS companies,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM classified
GROUP BY crawl_state
ORDER BY crawl_state;

\echo '=== P2: structured ATS waiting for auto-trust (by source_type) ==='
SELECT site.source_type, count(DISTINCT site.consolidation_key) AS companies
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled AND target.priority_tier = 'P2'
  AND site.verification_status = 'unverified'
  AND site.source_type <> 'generic_html'
  AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites verified
      WHERE verified.consolidation_key = site.consolidation_key
        AND verified.verification_status = 'verified'
        AND verified.crawl_enabled
  )
GROUP BY site.source_type
ORDER BY companies DESC;

\echo '=== P2 easy wins: rank-1 structured ATS still unverified (top 30) ==='
SELECT q.priority_score, q.canonical_name, q.candidate_1_url, q.candidate_1_source
FROM jobpush.career_site_review_workbench q
WHERE q.priority_tier = 'P2'
  AND q.action_status = 'REVIEW_CANDIDATES'
  AND q.candidate_1_source IN (
      'greenhouse', 'workday', 'lever', 'ashby', 'smartrecruiters',
      'icims', 'oracle_cloud', 'workable', 'jobvite', 'paylocity', 'rippling'
  )
ORDER BY q.priority_score DESC NULLS LAST, q.canonical_name
LIMIT 30;

\echo '=== P2: not searched yet (discovery_status=pending) ==='
SELECT count(*) AS not_searched
FROM jobpush.crawl_targets target
WHERE target.enabled AND target.priority_tier = 'P2'
  AND target.discovery_status = 'pending'
  AND target.last_discovery_at IS NULL
  AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites site
      WHERE site.consolidation_key = target.consolidation_key
        AND site.verification_status IN ('verified', 'unverified')
  );

\echo '=== P2: generic_html blockers (needs resolver/guess/manual) ==='
SELECT count(DISTINCT target.consolidation_key) AS companies_with_generic_only
FROM jobpush.crawl_targets target
JOIN jobpush.career_sites site USING (consolidation_key)
WHERE target.enabled AND target.priority_tier = 'P2'
  AND site.source_type = 'generic_html'
  AND site.verification_status = 'unverified'
  AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites verified
      WHERE verified.consolidation_key = target.consolidation_key
        AND verified.verification_status = 'verified'
        AND verified.crawl_enabled
  );

\echo '=== P2: searched but no retained candidate ==='
SELECT count(*) AS searched_no_candidate
FROM jobpush.crawl_targets target
WHERE target.enabled AND target.priority_tier = 'P2'
  AND target.discovery_status IN ('not_found', 'retry')
  AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites site
      WHERE site.consolidation_key = target.consolidation_key
  );
