#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -P pager=off -c "
UPDATE jobpush.career_sites
SET crawl_status = 'pending',
    consecutive_failures = 0,
    last_error = NULL,
    next_crawl_at = now(),
    updated_at = now()
WHERE source_type = 'icims'
  AND crawl_status = 'failed'
  AND last_error ILIKE '%did not expose a United States location option%';

SELECT priority_tier, source_type, count(*) AS due_sites
FROM jobpush.crawl_schedule_queue
WHERE is_due AND source_type='icims'
GROUP BY priority_tier, source_type
ORDER BY priority_tier;
"
