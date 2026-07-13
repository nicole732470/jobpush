#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -P pager=off -f "$SCRIPT_DIR/analysis/generic_resolver_eligibility_audit.sql"

echo
echo '=== Among jsonld-checked generic-only not-enabled: resolution status ==='
"${PSQL[@]}" -P pager=off <<'SQL'
WITH generic_only AS (
  SELECT DISTINCT ON (site.consolidation_key)
         target.priority_tier,
         site.consolidation_key,
         site.site_id,
         site.last_error,
         site.site_url
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled
    AND target.priority_tier IN ('P2','P3')
    AND site.verification_status = 'unverified'
    AND site.source_type = 'generic_html'
    AND site.crawl_enabled = FALSE
    AND coalesce(site.last_error,'') LIKE 'generic_jsonld_checked:%'
    AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites enabled
      WHERE enabled.consolidation_key = site.consolidation_key
        AND enabled.verification_status = 'verified'
        AND enabled.crawl_enabled
    )
    AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites structured
      WHERE structured.consolidation_key = site.consolidation_key
        AND structured.source_type <> 'generic_html'
        AND structured.verification_status IN ('verified','unverified')
    )
  ORDER BY site.consolidation_key, site.candidate_rank NULLS LAST,
           site.candidate_score DESC NULLS LAST, site.site_id
)
SELECT priority_tier,
       count(*) AS companies,
       count(*) FILTER (
         WHERE last_error LIKE 'generic_ats_resolution_attempted%'
            OR last_error LIKE 'generic_jsonld_checked:%'
       ) AS all_marked,
       count(*) FILTER (
         WHERE EXISTS (
           SELECT 1 FROM jobpush.career_sites s2
           WHERE s2.consolidation_key = generic_only.consolidation_key
             AND s2.source_type = 'generic_html'
             AND coalesce(s2.last_error,'') LIKE 'generic_ats_resolution_attempted%'
         )
       ) AS had_resolution_marker_on_any_generic
FROM generic_only
GROUP BY 1
ORDER BY 1;

SELECT count(*) AS resolver_fresh_eligible_exact_selector
FROM (
  SELECT DISTINCT ON (target.consolidation_key) site.site_id
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled
    AND target.priority_tier IN ('P2','P3')
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
    )
  ORDER BY target.consolidation_key, target.priority_tier, target.priority_score DESC NULLS LAST,
           site.candidate_score DESC NULLS LAST, site.candidate_rank NULLS LAST
) x;
SQL
