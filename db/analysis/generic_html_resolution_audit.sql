\pset pager off

\echo '=== P0/P1 generic_html domains ==='
SELECT
    site.normalized_domain,
    count(*) AS site_rows,
    count(DISTINCT site.consolidation_key) AS companies,
    max(site.candidate_score) AS max_candidate_score,
    string_agg(DISTINCT target.priority_tier, ', ' ORDER BY target.priority_tier) AS tiers,
    min(site.site_url) AS example_url
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier IN ('P0','P1')
  AND site.source_type = 'generic_html'
  AND site.verification_status = 'unverified'
GROUP BY site.normalized_domain
ORDER BY companies DESC, max_candidate_score DESC
LIMIT 80;

\echo '=== P0/P1 generic_html path patterns ==='
WITH parsed AS (
    SELECT
        regexp_replace(site.site_url, '^https?://[^/]+', '') AS path,
        site.normalized_domain,
        target.priority_tier
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P0','P1')
      AND site.source_type = 'generic_html'
      AND site.verification_status = 'unverified'
), bucketed AS (
    SELECT
        CASE
            WHEN path ILIKE '%workday%' THEN 'path_mentions_workday'
            WHEN path ILIKE '%greenhouse%' THEN 'path_mentions_greenhouse'
            WHEN path ILIKE '%lever%' THEN 'path_mentions_lever'
            WHEN path ILIKE '%icims%' THEN 'path_mentions_icims'
            WHEN path ILIKE '%successfactors%' THEN 'path_mentions_successfactors'
            WHEN path ILIKE '%jobs/search%' OR path ILIKE '%search-jobs%' OR path ILIKE '%job-search%' THEN 'job_search_path'
            WHEN path ILIKE '%careers%' THEN 'careers_path'
            WHEN path ILIKE '%jobs%' THEN 'jobs_path'
            WHEN path = '' OR path = '/' THEN 'homepage_or_root'
            ELSE 'other'
        END AS path_bucket,
        normalized_domain
    FROM parsed
)
SELECT
    path_bucket,
    count(*) AS site_rows,
    count(DISTINCT normalized_domain) AS domains
FROM bucketed
GROUP BY path_bucket
ORDER BY site_rows DESC;

\echo '=== P0/P1 generic_html high-value examples ==='
SELECT
    target.priority_tier,
    target.priority_score,
    target.canonical_name,
    site.site_id,
    site.candidate_rank,
    site.candidate_score,
    site.site_url,
    site.evidence_title
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier IN ('P0','P1')
  AND site.source_type = 'generic_html'
  AND site.verification_status = 'unverified'
ORDER BY target.priority_tier, target.priority_score DESC NULLS LAST, site.candidate_score DESC
LIMIT 120;

\echo '=== verified generic_html examples that already crawl successfully ==='
SELECT
    target.canonical_name,
    site.site_url,
    site.normalized_domain,
    site.last_success_at,
    run.target_job_count,
    run.review_job_count
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
LEFT JOIN LATERAL (
    SELECT run.target_job_count, run.review_job_count
    FROM jobpush.crawl_runs run
    WHERE run.site_id = site.site_id
      AND run.status = 'succeeded'
    ORDER BY run.finished_at DESC NULLS LAST, run.started_at DESC
    LIMIT 1
) run ON TRUE
WHERE target.enabled
  AND target.priority_tier IN ('P0','P1')
  AND site.source_type = 'generic_html'
  AND site.verification_status = 'verified'
  AND site.last_success_at IS NOT NULL
ORDER BY site.last_success_at DESC
LIMIT 50;
