#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

"/usr/bin/time" -p "${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/refresh/refresh_company_targets_consolidated.sql"
"/usr/bin/time" -p "${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/refresh/sync_crawl_targets.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT priority_tier, COUNT(*) AS active_crawl_targets
   FROM jobpush.crawl_targets
   WHERE enabled
   GROUP BY priority_tier
   ORDER BY CASE priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 ELSE 4 END;"

"${PSQL[@]}" -P pager=off -c \
  "SELECT COALESCE(crawl_priority_tier, 'NULL') AS tier, priority_score, COUNT(*) AS companies
   FROM jobpush.company_targets_consolidated
   GROUP BY 1, 2
   ORDER BY CASE COALESCE(crawl_priority_tier, 'NULL') WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 ELSE 4 END,
            priority_score DESC;"
