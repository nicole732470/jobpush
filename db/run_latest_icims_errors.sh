#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -P pager=off -c "
SELECT target.canonical_name,
       site.site_id,
       site.site_url,
       site.consecutive_failures,
       run.started_at,
       run.status,
       run.error_code,
       run.error_message
FROM jobpush.crawl_runs run
JOIN jobpush.career_sites site USING (site_id)
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.source_type = 'icims'
  AND run.status = 'failed'
ORDER BY run.started_at DESC
LIMIT 10;
"
