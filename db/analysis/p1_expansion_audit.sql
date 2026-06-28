\pset pager off

\echo '=== P1 structured candidates not enabled by source/rank ==='
WITH site_rollup AS (
    SELECT
        target.consolidation_key,
        target.canonical_name,
        target.priority_score,
        site.source_type,
        site.candidate_rank,
        site.site_url,
        site.verification_status,
        site.crawl_enabled,
        row_number() OVER (
            PARTITION BY target.consolidation_key
            ORDER BY site.candidate_rank NULLS LAST, site.candidate_score DESC NULLS LAST, site.site_id
        ) AS site_choice_rank
    FROM jobpush.crawl_targets target
    JOIN jobpush.career_sites site USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier = 'P1'
      AND site.verification_status = 'unverified'
      AND site.source_type <> 'generic_html'
      AND NOT EXISTS (
          SELECT 1
          FROM jobpush.career_sites verified
          WHERE verified.consolidation_key = target.consolidation_key
            AND verified.verification_status = 'verified'
      )
)
SELECT
    source_type,
    candidate_rank,
    COUNT(DISTINCT consolidation_key) AS companies
FROM site_rollup
GROUP BY source_type, candidate_rank
ORDER BY companies DESC, source_type, candidate_rank;

\echo '=== P1 structured candidates not enabled examples ==='
SELECT
    canonical_name,
    priority_score,
    source_type,
    candidate_rank,
    site_url
FROM (
    SELECT
        target.canonical_name,
        target.priority_score,
        site.source_type,
        site.candidate_rank,
        site.site_url,
        row_number() OVER (
            PARTITION BY target.consolidation_key
            ORDER BY site.candidate_rank NULLS LAST, site.candidate_score DESC NULLS LAST, site.site_id
        ) AS rn
    FROM jobpush.crawl_targets target
    JOIN jobpush.career_sites site USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier = 'P1'
      AND site.verification_status = 'unverified'
      AND site.source_type <> 'generic_html'
      AND NOT EXISTS (
          SELECT 1
          FROM jobpush.career_sites verified
          WHERE verified.consolidation_key = target.consolidation_key
            AND verified.verification_status = 'verified'
      )
) ranked
WHERE rn = 1
ORDER BY priority_score DESC NULLS LAST, canonical_name
LIMIT 80;

\echo '=== P1 pending targets: why not selected by current Tavily runner ==='
WITH site_rollup AS (
    SELECT
        consolidation_key,
        COUNT(*) FILTER (WHERE verification_status IN ('verified','unverified')) AS retained_candidates
    FROM jobpush.career_sites
    GROUP BY consolidation_key
)
SELECT
    CASE
        WHEN target.last_discovery_at IS NULL THEN 'last_discovery_at_is_null'
        ELSE 'last_discovery_at_exists'
    END AS discovery_timestamp_state,
    COALESCE(site.retained_candidates, 0) AS retained_candidate_count,
    COUNT(*) AS companies,
    MIN(target.priority_score) AS min_priority_score,
    MAX(target.priority_score) AS max_priority_score
FROM jobpush.crawl_targets target
LEFT JOIN site_rollup site USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier = 'P1'
  AND target.discovery_status = 'pending'
GROUP BY 1, 2
ORDER BY companies DESC, 1, 2;

\echo '=== P1 pending examples ==='
WITH site_rollup AS (
    SELECT
        consolidation_key,
        COUNT(*) FILTER (WHERE verification_status IN ('verified','unverified')) AS retained_candidates
    FROM jobpush.career_sites
    GROUP BY consolidation_key
)
SELECT
    target.canonical_name,
    target.priority_score,
    target.last_discovery_at,
    COALESCE(site.retained_candidates, 0) AS retained_candidates
FROM jobpush.crawl_targets target
LEFT JOIN site_rollup site USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier = 'P1'
  AND target.discovery_status = 'pending'
ORDER BY target.priority_score DESC NULLS LAST, target.canonical_name
LIMIT 80;

\echo '=== P1 generic HTML candidates by candidate rank ==='
SELECT
    site.candidate_rank,
    COUNT(DISTINCT target.consolidation_key) AS companies,
    COUNT(*) AS site_rows
FROM jobpush.crawl_targets target
JOIN jobpush.career_sites site USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier = 'P1'
  AND site.verification_status = 'unverified'
  AND site.source_type = 'generic_html'
  AND NOT EXISTS (
      SELECT 1
      FROM jobpush.career_sites verified
      WHERE verified.consolidation_key = target.consolidation_key
        AND verified.verification_status = 'verified'
  )
GROUP BY site.candidate_rank
ORDER BY site.candidate_rank NULLS LAST;

\echo '=== Top P1 generic HTML domains needing resolution ==='
SELECT
    site.normalized_domain,
    COUNT(DISTINCT target.consolidation_key) AS companies,
    COUNT(*) AS site_rows,
    ROUND(AVG(target.priority_score)::numeric, 2) AS avg_priority_score
FROM jobpush.crawl_targets target
JOIN jobpush.career_sites site USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier = 'P1'
  AND site.verification_status = 'unverified'
  AND site.source_type = 'generic_html'
  AND NOT EXISTS (
      SELECT 1
      FROM jobpush.career_sites verified
      WHERE verified.consolidation_key = target.consolidation_key
        AND verified.verification_status = 'verified'
  )
GROUP BY site.normalized_domain
ORDER BY companies DESC, avg_priority_score DESC NULLS LAST, site.normalized_domain
LIMIT 80;
