#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -P pager=off -c "
SELECT site.source_type,
       run.status,
       count(*) AS runs,
       min(run.started_at) AS first_started_at,
       max(run.started_at) AS last_started_at
FROM jobpush.crawl_runs run
JOIN jobpush.career_sites site USING (site_id)
WHERE run.status = 'running'
GROUP BY site.source_type, run.status
ORDER BY runs DESC, site.source_type;

SELECT run.run_id,
       run.batch_id,
       run.started_at,
       target.priority_tier,
       target.canonical_name,
       site.source_type,
       site.site_url
FROM jobpush.crawl_runs run
JOIN jobpush.career_sites site USING (site_id)
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE run.status = 'running'
ORDER BY run.started_at
LIMIT 30;
"
