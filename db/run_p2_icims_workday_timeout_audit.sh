#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -P pager=off <<'SQL'
SELECT source_type,
       crawl_status,
       count(*) AS sites,
       count(*) FILTER (WHERE coalesce(last_error, '') ILIKE '%timeout%' OR coalesce(last_error, '') ILIKE '%timed out%') AS timeout_sites
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier = 'P2'
  AND site.source_type IN ('icims', 'workday')
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
GROUP BY 1, 2
ORDER BY 1, 2;

SELECT target.priority_tier,
       site.source_type,
       site.site_id,
       target.canonical_name,
       site.crawl_status,
       site.consecutive_failures,
       left(coalesce(site.last_error, ''), 180) AS last_error,
       site.site_url
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier = 'P2'
  AND site.source_type IN ('icims', 'workday')
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND (
      site.crawl_status = 'failed'
      OR coalesce(site.last_error, '') ILIKE '%timeout%'
      OR coalesce(site.last_error, '') ILIKE '%timed out%'
  )
ORDER BY site.source_type, target.priority_score DESC NULLS LAST, site.site_id
LIMIT 50;
SQL
