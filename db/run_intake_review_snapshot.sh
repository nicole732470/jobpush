#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -P pager=off <<'SQL'
\echo === Structured unverified P2/P3 (company not enabled) ===
WITH not_enabled AS (
  SELECT DISTINCT ON (site.consolidation_key)
         target.priority_tier, site.source_type
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
SELECT priority_tier, source_type, count(*) AS companies
FROM not_enabled
GROUP BY 1,2
ORDER BY 1, companies DESC;

\echo === Top auto-trust reviewed_by (P2/P3 verified enabled) ===
SELECT site.reviewed_by, count(*) AS sites
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.priority_tier IN ('P2','P3')
  AND site.verification_status='verified'
  AND site.crawl_enabled
  AND coalesce(site.reviewed_by,'') LIKE 'system:%'
GROUP BY 1
ORDER BY sites DESC
LIMIT 12;
SQL
