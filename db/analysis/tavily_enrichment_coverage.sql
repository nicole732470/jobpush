\pset pager off

\echo '=== Historical Tavily coverage by current priority tier ==='
SELECT
    target.crawl_priority_tier,
    count(*) FILTER (WHERE feature.tavily_searched) AS searched_companies,
    count(*) FILTER (WHERE feature.retained_candidate_count > 0) AS with_candidates,
    count(*) FILTER (WHERE feature.structured_ats_candidate_count > 0) AS with_structured_ats,
    count(*) FILTER (WHERE feature.has_successful_crawl) AS with_successful_crawl
FROM jobpush.company_targets_consolidated target
LEFT JOIN jobpush.company_tavily_discovery_features feature USING (consolidation_key)
GROUP BY target.crawl_priority_tier
ORDER BY target.crawl_priority_tier;

\echo '=== Retained Tavily rank-1 source distribution ==='
SELECT
    coalesce(rank1_source_type, 'no_retained_candidate') AS rank1_source_type,
    count(*) AS companies
FROM jobpush.company_tavily_discovery_features
WHERE tavily_searched
GROUP BY 1
ORDER BY 2 DESC, 1;

\echo '=== External company attributes currently populated ==='
SELECT
    count(*) AS researched_companies,
    count(*) FILTER (WHERE industry IS NOT NULL) AS with_industry,
    count(*) FILTER (WHERE employee_count_min IS NOT NULL OR employee_count_max IS NOT NULL) AS with_employee_size,
    count(*) FILTER (WHERE headquarters_country IS NOT NULL) AS with_headquarters,
    count(*) FILTER (WHERE review_status = 'verified') AS verified_profiles
FROM jobpush.company_external_enrichment;
