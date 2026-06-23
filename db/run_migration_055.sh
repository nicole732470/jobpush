#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
echo "==> migration 055 THE OCC career site"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/055_the_occ_career_site.sql"
echo "==> hiring analysis"
"${PSQL[@]}" -P pager=off -f "$SCRIPT_DIR/analysis/the_occ_career_and_hiring.sql"
