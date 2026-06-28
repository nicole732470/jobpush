\pset pager off

\echo '=== Normal-discovery eligible companies: never searched only ==='
SELECT
    priority_tier,
    COUNT(*) AS eligible_companies
FROM jobpush.crawl_targets target
WHERE target.enabled
  AND target.priority_tier IN ('P0', 'P1', 'P2')
  AND target.discovery_status = 'pending'
  AND target.last_discovery_at IS NULL
  AND NOT EXISTS (
      SELECT 1
      FROM jobpush.career_sites site
      WHERE site.consolidation_key = target.consolidation_key
        AND site.verification_status IN ('verified', 'unverified')
  )
GROUP BY priority_tier
ORDER BY priority_tier;

\echo '=== Historical searched rows excluded from normal discovery ==='
SELECT
    priority_tier,
    discovery_status,
    COUNT(*) AS companies,
    COUNT(*) FILTER (WHERE last_discovery_error IS NOT NULL) AS with_error,
    MIN(last_discovery_at) AS oldest_discovery_at,
    MAX(last_discovery_at) AS newest_discovery_at
FROM jobpush.crawl_targets target
WHERE target.enabled
  AND target.priority_tier IN ('P0', 'P1', 'P2')
  AND target.last_discovery_at IS NOT NULL
  AND target.discovery_status IN ('pending', 'retry', 'not_found')
  AND NOT EXISTS (
      SELECT 1
      FROM jobpush.career_sites site
      WHERE site.consolidation_key = target.consolidation_key
        AND site.verification_status IN ('verified', 'unverified')
  )
GROUP BY priority_tier, discovery_status
ORDER BY priority_tier, discovery_status;

\echo '=== Recent Tavily run quality ==='
SELECT
    COALESCE(summary.run_id, run.run_id) AS run_id,
    COALESCE(summary.cohort, run.cohort) AS cohort,
    run.started_at,
    run.target_count,
    run.candidate_count,
    run.error_count,
    run.estimated_credits,
    COALESCE(
        summary.run_quality,
        CASE
            WHEN run.target_count > 0 AND run.error_count = run.target_count THEN 'legacy_full_batch_failed'
            WHEN run.error_count > 0 THEN 'legacy_partial_failures'
            WHEN run.candidate_count = 0 THEN 'legacy_completed_no_candidate'
            ELSE 'legacy_no_attempt_log'
        END
    ) AS run_quality,
    COALESCE(summary.failed_searches, run.error_count) AS failed_searches,
    summary.transient_failures,
    summary.searched_no_candidate
FROM jobpush.career_site_discovery_runs run
LEFT JOIN jobpush.career_site_discovery_attempt_summary summary USING (run_id)
ORDER BY run.started_at DESC
LIMIT 20;
