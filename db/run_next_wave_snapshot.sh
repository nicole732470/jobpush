#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -P pager=off <<'SQL'
\echo === Enabled + fresh eligible ===
SELECT target.priority_tier, count(DISTINCT target.consolidation_key) AS enabled
FROM jobpush.crawl_targets target
WHERE target.enabled AND target.priority_tier IN ('P2','P3')
  AND EXISTS (
    SELECT 1 FROM jobpush.career_sites site
    WHERE site.consolidation_key=target.consolidation_key
      AND site.verification_status='verified' AND site.crawl_enabled)
GROUP BY 1 ORDER BY 1;

SELECT count(*) AS resolver_fresh_eligible
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
  ORDER BY target.consolidation_key, site.candidate_score DESC NULLS LAST
) x;

\echo === Workday unverified (company not enabled) ===
WITH not_enabled AS (
  SELECT DISTINCT ON (site.consolidation_key)
         target.priority_tier, site.site_id, site.site_url, site.normalized_domain,
         site.discovery_source, site.candidate_score
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled AND target.priority_tier IN ('P2','P3')
    AND site.verification_status='unverified'
    AND site.source_type='workday'
    AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites e
      WHERE e.consolidation_key=site.consolidation_key
        AND e.verification_status='verified' AND e.crawl_enabled)
  ORDER BY site.consolidation_key, site.candidate_rank NULLS LAST, site.candidate_score DESC NULLS LAST, site.site_id
)
SELECT priority_tier, count(*) AS companies,
       count(*) FILTER (WHERE site_url ~* '/job/') AS looks_like_job_detail,
       count(*) FILTER (WHERE site_url ~* '/(d|fx)/') AS looks_like_board
FROM not_enabled
GROUP BY 1 ORDER BY 1;

SELECT priority_tier, left(site_url,120) AS url, discovery_source
FROM (
  SELECT DISTINCT ON (site.consolidation_key)
         target.priority_tier, site.site_url, site.discovery_source
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled AND target.priority_tier IN ('P2','P3')
    AND site.verification_status='unverified' AND site.source_type='workday'
    AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites e
      WHERE e.consolidation_key=site.consolidation_key
        AND e.verification_status='verified' AND e.crawl_enabled)
  ORDER BY site.consolidation_key, site.candidate_rank NULLS LAST, site.candidate_score DESC NULLS LAST, site.site_id
) s
ORDER BY 1,2
LIMIT 45;
SQL
