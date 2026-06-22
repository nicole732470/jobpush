#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "==> sync crawl_targets from company_targets_consolidated"
"${PSQL[@]}" -f "$SCRIPT_DIR/refresh/sync_crawl_targets.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT priority_tier, COUNT(*) AS active_crawl_targets
   FROM jobpush.crawl_targets
   WHERE enabled
   GROUP BY priority_tier
   ORDER BY priority_tier;"
