\pset pager off

\echo '=== Generic resolver eligible (default criteria, P2/P3) ==='
SELECT count(*) AS eligible
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier IN ('P2', 'P3')
  AND site.source_type = 'generic_html'
  AND site.verification_status = 'unverified'
  AND site.crawl_enabled = FALSE
  AND COALESCE(site.last_error, '') NOT LIKE 'generic_ats_resolution_attempted%'
  AND NOT EXISTS (
      SELECT 1
      FROM jobpush.career_sites structured
      WHERE structured.consolidation_key = site.consolidation_key
        AND structured.source_type <> 'generic_html'
        AND structured.verification_status IN ('verified', 'unverified')
  );

\echo '=== Blocked: already resolution_attempted (P2/P3 generic_html) ==='
SELECT count(DISTINCT site.consolidation_key) AS companies
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier IN ('P2', 'P3')
  AND site.source_type = 'generic_html'
  AND site.verification_status = 'unverified'
  AND site.crawl_enabled = FALSE
  AND COALESCE(site.last_error, '') LIKE 'generic_ats_resolution_attempted%';

\echo '=== Blocked: has other structured/unverified candidate (P2/P3) ==='
SELECT count(DISTINCT site.consolidation_key) AS companies
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier IN ('P2', 'P3')
  AND site.source_type = 'generic_html'
  AND site.verification_status = 'unverified'
  AND site.crawl_enabled = FALSE
  AND EXISTS (
      SELECT 1
      FROM jobpush.career_sites structured
      WHERE structured.consolidation_key = site.consolidation_key
        AND structured.source_type <> 'generic_html'
        AND structured.verification_status IN ('verified', 'unverified')
  );

\echo '=== Retry-eligible (attempted before, no structured sibling, P2/P3) ==='
SELECT count(DISTINCT site.consolidation_key) AS companies
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier IN ('P2', 'P3')
  AND site.source_type = 'generic_html'
  AND site.verification_status = 'unverified'
  AND site.crawl_enabled = FALSE
  AND COALESCE(site.last_error, '') LIKE 'generic_ats_resolution_attempted%'
  AND NOT EXISTS (
      SELECT 1
      FROM jobpush.career_sites structured
      WHERE structured.consolidation_key = site.consolidation_key
        AND structured.source_type <> 'generic_html'
        AND structured.verification_status IN ('verified', 'unverified')
  );

\echo '=== Rank-1 generic_html unverified (workbench backlog, P2/P3) ==='
SELECT count(DISTINCT workbench.consolidation_key) AS companies
FROM jobpush.career_site_review_workbench workbench
WHERE workbench.priority_tier IN ('P2', 'P3')
  AND workbench.action_status = 'REVIEW_CANDIDATES'
  AND workbench.candidate_1_source = 'generic_html';

\echo '=== Resolver if we use rank-1 generic only (ignore structured sibling block) ==='
WITH rank1 AS (
    SELECT DISTINCT ON (site.consolidation_key)
           site.consolidation_key,
           site.site_id,
           site.last_error
    FROM jobpush.career_sites site
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    WHERE target.enabled
      AND target.priority_tier IN ('P2', 'P3')
      AND site.verification_status = 'unverified'
      AND NOT EXISTS (
          SELECT 1 FROM jobpush.career_sites v
          WHERE v.consolidation_key = site.consolidation_key
            AND v.verification_status = 'verified'
      )
    ORDER BY site.consolidation_key, site.candidate_rank NULLS LAST, site.candidate_score DESC NULLS LAST, site.site_id
)
SELECT
    count(*) FILTER (WHERE site.last_error NOT LIKE 'generic_ats_resolution_attempted%') AS fresh_rank1_unverified,
    count(*) FILTER (WHERE site.last_error LIKE 'generic_ats_resolution_attempted%') AS attempted_rank1_unverified
FROM rank1 r
JOIN jobpush.career_sites site ON site.site_id = r.site_id
WHERE site.source_type = 'generic_html'
  AND site.crawl_enabled = FALSE;
