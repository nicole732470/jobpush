#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -P pager=off <<'SQL'
SELECT site.site_id,
       site.source_type,
       target.canonical_name,
       site.consecutive_failures,
       left(coalesce(site.last_error, ''), 300) AS last_error,
       site.site_url
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier = 'P2'
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.crawl_status = 'failed'
ORDER BY target.priority_score DESC NULLS LAST, site.source_type, site.site_id;
SQL
