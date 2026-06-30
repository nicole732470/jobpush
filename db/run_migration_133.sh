#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -v ON_ERROR_STOP=1 -P pager=off \
  -f "$SCRIPT_DIR/migrations/133_profile_avoid_rules_facilities_store_service.sql"
