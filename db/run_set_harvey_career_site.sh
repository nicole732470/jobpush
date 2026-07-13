#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
echo "==> seed Harvey AI (harvey) + verify Ashby careers board"
"${PSQL[@]}" -P pager=off -f "$SCRIPT_DIR/ops/set_harvey_career_site.sql"
