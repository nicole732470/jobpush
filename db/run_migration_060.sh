#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/migrations/060_conservative_local_us_scope.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT priority_tier, source_type, scope_method, count(*) AS sites,
          count(*) FILTER (WHERE is_due) AS due
   FROM jobpush.crawl_schedule_queue
   GROUP BY priority_tier, source_type, scope_method
   ORDER BY priority_tier, source_type;"
