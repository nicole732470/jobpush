#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "==> set Google / Alphabet to P0"
"${PSQL[@]}" -f "$SCRIPT_DIR/manual/set_google_p0.sql"

echo "==> PG&E role analysis"
"${PSQL[@]}" -P pager=off -f "$SCRIPT_DIR/analysis/pge_roles.sql"
