\pset pager off

\echo '=== Tavily discovery run ledger ==='
SELECT
    run_id,
    cohort,
    target_count,
    candidate_count,
    error_count,
    estimated_credits,
    status,
    started_at,
    finished_at
FROM jobpush.career_site_discovery_runs
ORDER BY started_at NULLS LAST, run_id;

\echo '=== Tavily discovery totals ==='
SELECT
    count(*) AS runs,
    sum(target_count) AS searched_companies,
    sum(candidate_count) AS retained_candidates,
    sum(error_count) AS search_errors,
    sum(estimated_credits) AS estimated_credits
FROM jobpush.career_site_discovery_runs;

\echo '=== Career-site candidate inventory by verification/source ==='
SELECT
    verification_status,
    source_type,
    count(*) AS site_rows,
    count(DISTINCT consolidation_key) AS companies
FROM jobpush.career_sites
GROUP BY 1, 2
ORDER BY 1, 2;

\echo '=== P-tier company website coverage ==='
WITH site_rollup AS (
    SELECT
        consolidation_key,
        bool_or(verification_status = 'verified') AS has_verified_site,
        bool_or(verification_status IN ('verified', 'unverified')) AS has_retained_candidate,
        bool_or(crawl_enabled) AS has_crawl_enabled_site,
        bool_or(last_success_at IS NOT NULL) AS has_successful_crawl
    FROM jobpush.career_sites
    GROUP BY consolidation_key
)
SELECT
    target.priority_tier,
    count(*) AS companies,
    count(*) FILTER (WHERE rollup.has_retained_candidate) AS with_candidate_or_verified,
    count(*) FILTER (WHERE rollup.has_verified_site) AS with_verified_site,
    count(*) FILTER (WHERE rollup.has_crawl_enabled_site) AS with_crawl_enabled_site,
    count(*) FILTER (WHERE rollup.has_successful_crawl) AS with_successful_crawl,
    count(*) FILTER (WHERE NOT coalesce(rollup.has_retained_candidate, false)) AS no_retained_candidate
FROM jobpush.crawl_targets target
LEFT JOIN site_rollup rollup USING (consolidation_key)
WHERE target.enabled
GROUP BY 1
ORDER BY 1;

\echo '=== Company external enrichment visibility ==='
SELECT
    coalesce(enrichment_state, 'view_missing') AS enrichment_state,
    count(*) AS companies
FROM jobpush.company_priority_enrichment_workbench
GROUP BY 1
ORDER BY 1;

\echo '=== Structured company enrichment examples ==='
SELECT
    canonical_name,
    crawl_priority_tier,
    external_industry,
    external_headquarters_city,
    employee_count_min,
    founded_year,
    official_website_url,
    left(company_description, 180) AS description_preview
FROM jobpush.company_priority_enrichment_workbench
WHERE enrichment_state <> 'not_researched'
ORDER BY priority_score DESC NULLS LAST, canonical_name
LIMIT 30;
