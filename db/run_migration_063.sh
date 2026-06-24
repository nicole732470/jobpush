#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/migrations/063_icims_auto_trust_health_gate.sql"
"${PSQL[@]}" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/migrations/048_crawl_schedule_and_health.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT source_type, reviewed_by, verification_status, crawl_enabled, count(*)
   FROM jobpush.career_sites
   WHERE source_type='icims'
   GROUP BY 1,2,3,4 ORDER BY 3,2 NULLS FIRST;"
