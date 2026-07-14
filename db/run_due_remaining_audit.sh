#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -P pager=off -c "
SELECT priority_tier, count(*) AS due_now
FROM jobpush.crawl_schedule_queue
WHERE is_due AND crawl_status <> 'running'
GROUP BY 1 ORDER BY 1;
"
