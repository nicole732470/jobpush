#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "==> company_targets_consolidated only"
/usr/bin/time -p "${PSQL[@]}" -c '\timing on' \
  -f "$SCRIPT_DIR/refresh/refresh_company_targets_consolidated.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT COUNT(*) AS consolidated_rows, MAX(priority_score) AS max_priority
   FROM jobpush.company_targets_consolidated;"
