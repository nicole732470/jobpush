\pset pager off

\echo '=== Tavily funnel: searched -> ingested -> crawling ==='
WITH tavily_searched AS (
    SELECT DISTINCT ON (consolidation_key)
           consolidation_key,
           canonical_name,
           search_succeeded,
           candidate_count,
           attempted_at
    FROM jobpush.career_site_discovery_attempts
    ORDER BY consolidation_key, attempted_at DESC
),
site_rollup AS (
    SELECT
        consolidation_key,
        count(*) AS site_rows,
        count(*) FILTER (WHERE discovery_source = 'tavily_basic') AS tavily_site_rows,
        bool_or(verification_status = 'verified') AS has_verified,
        bool_or(verification_status IN ('verified', 'unverified')) AS has_retained,
        bool_or(crawl_enabled) AS crawl_enabled,
        bool_or(last_success_at IS NOT NULL) AS crawl_succeeded
    FROM jobpush.career_sites
    GROUP BY consolidation_key
)
SELECT
    count(*) AS tavily_searched_companies,
    count(*) FILTER (WHERE ts.search_succeeded) AS search_ok,
    count(*) FILTER (WHERE ts.search_succeeded AND ts.candidate_count > 0) AS had_candidates,
    count(*) FILTER (WHERE sr.has_retained) AS ingested_has_site_row,
    count(*) FILTER (WHERE sr.tavily_site_rows > 0) AS ingested_from_tavily,
    count(*) FILTER (WHERE sr.has_verified) AS verified_site,
    count(*) FILTER (WHERE sr.crawl_enabled) AS crawl_enabled,
    count(*) FILTER (WHERE sr.crawl_succeeded) AS actively_crawling_ok,
    count(*) FILTER (WHERE ts.search_succeeded AND ts.candidate_count > 0 AND NOT coalesce(sr.has_retained, false)) AS had_candidates_not_ingested,
    count(*) FILTER (WHERE ts.search_succeeded AND ts.candidate_count = 0) AS searched_no_candidate,
    count(*) FILTER (WHERE NOT ts.search_succeeded) AS search_failed
FROM tavily_searched ts
LEFT JOIN site_rollup sr USING (consolidation_key);

\echo '=== Tavily searched but not yet verified/crawling (top 30) ==='
WITH tavily_searched AS (
    SELECT DISTINCT ON (consolidation_key)
           consolidation_key, canonical_name, candidate_count, attempted_at
    FROM jobpush.career_site_discovery_attempts
    WHERE search_succeeded AND candidate_count > 0
    ORDER BY consolidation_key, attempted_at DESC
),
site_rollup AS (
    SELECT consolidation_key,
           bool_or(verification_status = 'verified') AS has_verified,
           bool_or(crawl_enabled) AS crawl_enabled,
           string_agg(site_url, ' | ' ORDER BY candidate_rank NULLS LAST, site_id) AS urls
    FROM jobpush.career_sites
    GROUP BY consolidation_key
)
SELECT ts.consolidation_key,
       ts.canonical_name,
       target.priority_tier,
       target.discovery_status,
       ts.candidate_count,
       coalesce(sr.has_verified, false) AS verified,
       coalesce(sr.crawl_enabled, false) AS crawling,
       left(sr.urls, 120) AS site_urls
FROM tavily_searched ts
JOIN jobpush.crawl_targets target USING (consolidation_key)
LEFT JOIN site_rollup sr USING (consolidation_key)
WHERE NOT coalesce(sr.has_verified, false)
   OR NOT coalesce(sr.crawl_enabled, false)
ORDER BY target.priority_tier, ts.candidate_count DESC, ts.canonical_name
LIMIT 30;

\echo '=== Remaining backlog: never Tavily-searched P0-P2 with no site ==='
SELECT target.priority_tier,
       count(*) AS companies
FROM jobpush.crawl_targets target
WHERE target.enabled
  AND target.priority_tier IN ('P0', 'P1', 'P2')
  AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_site_discovery_attempts att
      WHERE att.consolidation_key = target.consolidation_key
  )
  AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites site
      WHERE site.consolidation_key = target.consolidation_key
        AND site.verification_status IN ('verified', 'unverified')
  )
GROUP BY target.priority_tier
ORDER BY target.priority_tier;

\echo '=== Discovery status for Tavily-searched companies ==='
SELECT target.discovery_status,
       count(*) AS companies,
       count(*) FILTER (WHERE site.has_verified) AS with_verified,
       count(*) FILTER (WHERE site.crawl_enabled) AS crawling
FROM (
    SELECT DISTINCT consolidation_key
    FROM jobpush.career_site_discovery_attempts
) att
JOIN jobpush.crawl_targets target USING (consolidation_key)
LEFT JOIN LATERAL (
    SELECT bool_or(verification_status = 'verified') AS has_verified,
           bool_or(crawl_enabled) AS crawl_enabled
    FROM jobpush.career_sites s
    WHERE s.consolidation_key = target.consolidation_key
) site ON true
GROUP BY target.discovery_status
ORDER BY companies DESC;

\echo '=== Tavily run totals ==='
SELECT count(*) AS runs,
       sum(target_count) AS searched,
       sum(candidate_count) AS candidates,
       sum(error_count) AS errors,
       sum(estimated_credits) AS credits
FROM jobpush.career_site_discovery_runs;
