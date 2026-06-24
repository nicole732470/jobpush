#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/migrations/065_profile_title_rules_v2_table_driven.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT classification_status, rule_version, count(*) AS titles
   FROM jobpush.job_title_labels
   GROUP BY 1,2
   ORDER BY 1,2;"
"${PSQL[@]}" -P pager=off -c \
  "SELECT role_status, count(*) AS active_us_jobs
   FROM jobpush.dashboard_jobs
   GROUP BY 1
   ORDER BY 1;"
