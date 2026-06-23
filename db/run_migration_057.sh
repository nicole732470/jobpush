#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/migrations/057_consolidate_career_site_review_views.sql"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -c \
  "SELECT action_status, COUNT(*) AS companies
   FROM jobpush.career_site_review_workbench
   GROUP BY action_status
   ORDER BY action_status;"
