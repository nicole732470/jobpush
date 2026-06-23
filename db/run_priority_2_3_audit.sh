#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -P pager=off -f "$SCRIPT_DIR/analysis/priority_score_2_and_3_breakdown.sql"
