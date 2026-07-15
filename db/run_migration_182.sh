#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/migrations/182_unify_platform_and_export_eligibility.sql"
"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/refresh/refresh_dashboard_jobs_fast.sql"
