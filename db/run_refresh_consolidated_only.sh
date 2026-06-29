#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/refresh/refresh_company_targets_consolidated.sql"
"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/refresh/sync_crawl_targets.sql"
"${PSQL[@]}" -P pager=off -c \
  "SELECT priority_tier, COUNT(*) AS active_crawl_targets
   FROM jobpush.crawl_targets
   WHERE enabled
   GROUP BY priority_tier
   ORDER BY priority_tier;"
