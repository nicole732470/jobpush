#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"
echo "==> migration 042 Texas Instruments Oracle metadata"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/042_texas_instruments_oracle_adapter.sql"
"${PSQL[@]}" -P pager=off -c \
  "SELECT site_id,source_type,source_key,target_country_code,site_url
   FROM jobpush.career_sites WHERE consolidation_key='75-0289970' ORDER BY site_id;"
