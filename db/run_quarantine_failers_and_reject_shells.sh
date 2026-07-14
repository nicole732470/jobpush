#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/ops/quarantine_failers_and_reject_shells.sql"
bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"
