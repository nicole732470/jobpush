#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "==> migration 024 career-site discovery pilot"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/024_career_site_discovery_pilot.sql"
