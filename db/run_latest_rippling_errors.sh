#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -P pager=off -c "
SELECT run.started_at,
       target.priority_tier,
       target.canonical_name,
       site.site_id,
       site.site_url,
       site.crawl_status,
       site.consecutive_failures,
       left(site.last_error, 500) AS last_error,
       run.status,
       run.error_code,
       left(run.error_message, 500) AS run_error
FROM jobpush.crawl_runs run
JOIN jobpush.career_sites site USING (site_id)
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE site.source_type = 'rippling'
ORDER BY run.started_at DESC
LIMIT 20;
"
