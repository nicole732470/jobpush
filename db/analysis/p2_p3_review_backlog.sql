\pset pager off

\echo '=== P2/P3 review backlog by source (unverified rank-1) ==='
WITH rank1 AS (
    SELECT DISTINCT ON (site.consolidation_key)
           site.consolidation_key,
           site.site_id,
           site.source_type,
           site.site_url,
           site.verification_status,
           site.crawl_enabled
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
SELECT source_type,
       count(*) AS companies,
       count(*) FILTER (WHERE source_type IN (
           'greenhouse','workday','lever','ashby','smartrecruiters','icims','oracle_cloud','jobvite','paylocity','rippling','ultipro','workable'
       )) AS structured_ats_eligible,
       count(*) FILTER (WHERE source_type = 'generic_html') AS generic_html_manual
FROM rank1
GROUP BY source_type
ORDER BY companies DESC;

\echo '=== P2/P3 discovery status ==='
SELECT target.priority_tier,
       target.discovery_status,
       count(*) AS companies
FROM jobpush.crawl_targets target
WHERE target.enabled
  AND target.priority_tier IN ('P2', 'P3')
GROUP BY 1, 2
ORDER BY 1, 2;

\echo '=== P2/P3 verified + crawling ==='
SELECT target.priority_tier,
       count(DISTINCT target.consolidation_key) AS companies,
       count(DISTINCT target.consolidation_key) FILTER (WHERE site.verified) AS verified,
       count(DISTINCT target.consolidation_key) FILTER (WHERE site.crawling) AS crawl_enabled,
       count(DISTINCT target.consolidation_key) FILTER (WHERE site.succeeded) AS crawl_ok
FROM jobpush.crawl_targets target
LEFT JOIN LATERAL (
    SELECT bool_or(s.verification_status = 'verified') AS verified,
           bool_or(s.crawl_enabled) AS crawling,
           bool_or(s.last_success_at IS NOT NULL) AS succeeded
    FROM jobpush.career_sites s
    WHERE s.consolidation_key = target.consolidation_key
) site ON true
WHERE target.enabled
  AND target.priority_tier IN ('P2', 'P3')
GROUP BY 1
ORDER BY 1;

\echo '=== P2/P3 manual review queue sample (generic_html rank-1, top 20) ==='
SELECT workbench.consolidation_key,
       workbench.canonical_name,
       workbench.priority_tier,
       workbench.candidate_1_url,
       workbench.candidate_1_source
FROM jobpush.career_site_review_workbench workbench
WHERE workbench.priority_tier IN ('P2', 'P3')
  AND workbench.action_status = 'REVIEW_CANDIDATES'
  AND workbench.candidate_1_source = 'generic_html'
ORDER BY workbench.priority_tier, workbench.priority_score DESC NULLS LAST
LIMIT 20;
