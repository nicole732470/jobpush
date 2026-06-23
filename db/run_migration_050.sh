#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/migrations/050_career_site_review_dashboard.sql"
"${PSQL[@]}" -P pager=off -c \
  "SELECT * FROM jobpush.career_site_company_dashboard
   WHERE priority_tier='P0' ORDER BY dashboard_rank;
   SELECT * FROM jobpush.career_site_review_precision
   ORDER BY source_type, candidate_rank;"
