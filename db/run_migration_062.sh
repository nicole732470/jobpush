#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/migrations/062_auto_trust_structured_ats.sql"
"${PSQL[@]}" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/migrations/048_crawl_schedule_and_health.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT source_type, reviewed_by, count(*) AS sites,
          count(*) FILTER (WHERE next_crawl_at <= now()) AS due
   FROM jobpush.career_sites
   WHERE verification_status='verified' AND crawl_enabled
   GROUP BY 1,2 ORDER BY 1,2;"
