#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "==> migration 023 crawl targets and career sites"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/023_crawl_targets_and_career_sites.sql"

echo "==> sync P0/P1/P2 crawl targets"
"${PSQL[@]}" -f "$SCRIPT_DIR/refresh/sync_crawl_targets.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT priority_tier,
          COUNT(*) AS companies,
          ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_active_queue
   FROM jobpush.crawl_targets
   WHERE enabled
   GROUP BY priority_tier
   ORDER BY priority_tier;"

"${PSQL[@]}" -P pager=off -c \
  "SELECT COUNT(*) AS career_sites FROM jobpush.career_sites;"
