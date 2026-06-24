#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/migrations/068_site_selection_and_new_adapters.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT source_type, reviewed_by, verification_status, count(*) AS sites
   FROM jobpush.career_sites
   WHERE source_type IN ('lever','ashby','smartrecruiters')
   GROUP BY 1,2,3
   ORDER BY 1,2,3;"
"${PSQL[@]}" -P pager=off -c \
  "SELECT priority_tier, source_type, count(*) AS schedulable, count(*) FILTER (WHERE is_due) AS due
   FROM jobpush.crawl_schedule_queue
   GROUP BY 1,2
   ORDER BY 1,2;"
