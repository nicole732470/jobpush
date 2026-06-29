\pset pager off

\echo '=== P1 structured candidates not enabled ==='
SELECT
    site.source_type,
    COUNT(DISTINCT site.consolidation_key) AS companies,
    COUNT(*) AS site_rows,
    MIN(site.site_url) AS example_url
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier = 'P1'
  AND site.verification_status = 'unverified'
  AND site.source_type <> 'generic_html'
  AND NOT EXISTS (
      SELECT 1
      FROM jobpush.career_sites verified
      WHERE verified.consolidation_key = site.consolidation_key
        AND verified.verification_status = 'verified'
        AND verified.crawl_enabled
  )
GROUP BY site.source_type
ORDER BY companies DESC, site.source_type;

\echo '=== P1 generic high-value URL patterns ==='
WITH generic AS (
  SELECT DISTINCT ON (target.consolidation_key)
      target.canonical_name,
      target.priority_score,
      site.site_url,
      site.normalized_domain,
      regexp_replace(site.site_url, '^https?://[^/]+', '') AS path
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled
    AND target.priority_tier = 'P1'
    AND site.source_type = 'generic_html'
    AND site.verification_status = 'unverified'
    AND site.crawl_enabled = FALSE
    AND NOT EXISTS (
      SELECT 1
      FROM jobpush.career_sites verified
      WHERE verified.consolidation_key = site.consolidation_key
        AND verified.verification_status = 'verified'
        AND verified.crawl_enabled
    )
  ORDER BY target.consolidation_key, target.priority_score DESC NULLS LAST,
           site.candidate_score DESC NULLS LAST
)
SELECT
  CASE
    WHEN normalized_domain LIKE '%.freshteam.com' THEN 'freshteam_domain'
    WHEN normalized_domain LIKE '%.teamtailor.com' THEN 'teamtailor_domain'
    WHEN normalized_domain LIKE '%.jobs' THEN 'dot_jobs_domain'
    WHEN normalized_domain LIKE 'jobs.%' THEN 'jobs_subdomain'
    WHEN path ILIKE '%search-jobs%' OR path ILIKE '%search/jobs%' OR path ILIKE '%job-search%' THEN 'search_jobs_path'
    WHEN path ILIKE '%/jobs%' THEN 'jobs_path'
    WHEN path ILIKE '%/careers%' OR path ILIKE '%/career%' THEN 'careers_path'
    ELSE 'other'
  END AS pattern,
  COUNT(*) AS companies,
  MIN(site_url) AS example_url
FROM generic
GROUP BY 1
ORDER BY companies DESC, pattern;
