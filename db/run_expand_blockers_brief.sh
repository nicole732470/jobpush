#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -P pager=off <<'SQL'
\echo === Coverage: enabled vs targets ===
SELECT target.priority_tier,
       count(*) AS enabled_targets,
       count(*) FILTER (
         WHERE EXISTS (
           SELECT 1 FROM jobpush.career_sites s
           WHERE s.consolidation_key=target.consolidation_key
             AND s.verification_status='verified' AND s.crawl_enabled)
       ) AS with_verified_site
FROM jobpush.crawl_targets target
WHERE target.enabled AND target.priority_tier IN ('P2','P3')
GROUP BY 1 ORDER BY 1;

\echo === Rank1 not-enabled blockers (P2/P3) ===
WITH rank1 AS (
  SELECT DISTINCT ON (site.consolidation_key)
         target.priority_tier, site.source_type, site.verification_status,
         site.crawl_enabled, site.last_error, site.site_url
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled AND target.priority_tier IN ('P2','P3')
    AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites e
      WHERE e.consolidation_key=site.consolidation_key
        AND e.verification_status='verified' AND e.crawl_enabled)
  ORDER BY site.consolidation_key, site.candidate_rank NULLS LAST,
           site.candidate_score DESC NULLS LAST, site.site_id
)
SELECT priority_tier,
  count(*) AS companies,
  count(*) FILTER (WHERE source_type='generic_html') AS generic,
  count(*) FILTER (WHERE source_type<>'generic_html' AND verification_status='unverified') AS structured_unverified,
  count(*) FILTER (WHERE source_type<>'generic_html' AND verification_status='rejected') AS structured_rejected_rank1,
  count(*) FILTER (WHERE source_type='generic_html' AND coalesce(last_error,'') LIKE 'generic_ats_resolution_attempted:v2%') AS resolver_attempted_v2,
  count(*) FILTER (WHERE source_type='generic_html' AND coalesce(last_error,'') NOT LIKE 'generic_ats_resolution_attempted:v2%') AS resolver_freshish
FROM rank1
GROUP BY 1 ORDER BY 1;

\echo === Structured unverified remaining (not enabled) ===
WITH not_enabled AS (
  SELECT DISTINCT ON (site.consolidation_key)
         target.priority_tier, site.source_type, left(site.site_url,100) AS url
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled AND target.priority_tier IN ('P2','P3')
    AND site.verification_status='unverified'
    AND site.source_type <> 'generic_html'
    AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites e
      WHERE e.consolidation_key=site.consolidation_key
        AND e.verification_status='verified' AND e.crawl_enabled)
  ORDER BY site.consolidation_key, site.candidate_rank NULLS LAST, site.candidate_score DESC NULLS LAST, site.site_id
)
SELECT priority_tier, source_type, count(*) AS n FROM not_enabled
GROUP BY 1,2 ORDER BY 1, n DESC;

\echo === Verified enabled crawl health (recent auto-trust 7d) ===
SELECT
  count(*) AS verified_7d,
  count(*) FILTER (WHERE site.last_success_at IS NOT NULL) AS succeeded_once,
  count(*) FILTER (WHERE site.last_success_at IS NULL) AS never_succeeded,
  count(*) FILTER (WHERE site.crawl_status='failed') AS failed_now,
  count(*) FILTER (WHERE q.is_due) AS due_now
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
LEFT JOIN jobpush.crawl_schedule_queue q USING (site_id)
WHERE target.priority_tier IN ('P2','P3')
  AND site.reviewed_by='system:structured-ats-best-v5'
  AND site.reviewed_at >= now() - interval '7 days'
  AND site.verification_status='verified'
  AND site.crawl_enabled;

\echo === Fresh resolver still eligible ===
SELECT count(*) AS fresh_eligible
FROM (
  SELECT DISTINCT ON (target.consolidation_key) site.site_id
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled AND target.priority_tier IN ('P2','P3')
    AND site.source_type='generic_html' AND site.verification_status='unverified'
    AND site.crawl_enabled=FALSE
    AND COALESCE(site.last_error,'') NOT LIKE 'generic_ats_resolution_attempted:v2%'
    AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites structured
      WHERE structured.consolidation_key=site.consolidation_key
        AND structured.source_type<>'generic_html'
        AND structured.verification_status IN ('verified','unverified'))
) x;

\echo === New grad coverage ===
SELECT seniority_bucket, count(*) FROM jobpush.dashboard_jobs_fast
WHERE seniority_bucket IN ('new_grad','entry_level','internship')
GROUP BY 1 ORDER BY 1;
SQL
