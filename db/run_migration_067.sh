#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/migrations/067_dashboard_daily_activity_us_active.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT * FROM jobpush.dashboard_daily_activity ORDER BY activity_date DESC LIMIT 1;"
