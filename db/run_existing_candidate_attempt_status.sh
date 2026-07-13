#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -P pager=off <<'SQL'
WITH rank1 AS (
  SELECT DISTINCT ON (site.consolidation_key)
         target.priority_tier, site.*
  FROM jobpush.career_sites site
  JOIN jobpush.crawl_targets target USING (consolidation_key)
  WHERE target.enabled
    AND target.priority_tier IN ('P2','P3')
    AND site.verification_status = 'unverified'
    AND NOT EXISTS (
      SELECT 1 FROM jobpush.career_sites enabled
      WHERE enabled.consolidation_key = site.consolidation_key
        AND enabled.verification_status = 'verified'
        AND enabled.crawl_enabled
    )
  ORDER BY site.consolidation_key, site.candidate_rank NULLS LAST,
           site.candidate_score DESC NULLS LAST, site.site_id
)
SELECT priority_tier,
       count(*) FILTER (WHERE source_type='generic_html') AS generic_rank1,
       count(*) FILTER (WHERE source_type='generic_html' AND last_error LIKE 'generic_jsonld_checked:%') AS jsonld_attempted,
       count(*) FILTER (WHERE source_type='generic_html' AND coalesce(last_error,'') NOT LIKE 'generic_jsonld_checked:%') AS jsonld_not_attempted,
       count(*) FILTER (WHERE source_type<>'generic_html') AS structured_unverified
FROM rank1
GROUP BY priority_tier
ORDER BY priority_tier;

SELECT target.priority_tier,
       count(*) AS promoted_generic_sites,
       count(*) FILTER (WHERE site.last_success_at IS NOT NULL) AS crawled_successfully
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.priority_tier IN ('P2','P3')
  AND site.reviewed_by='system:generic-jsonld-v1'
GROUP BY target.priority_tier
ORDER BY target.priority_tier;
SQL
