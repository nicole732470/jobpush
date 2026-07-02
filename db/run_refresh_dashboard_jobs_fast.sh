#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "==> refresh dashboard jobs fast table"
"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/refresh/refresh_dashboard_jobs_fast.sql"
