#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"
echo "==> migration 041 JPMorgan Oracle adapter metadata"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/041_jpmorgan_oracle_adapter.sql"
"${PSQL[@]}" -P pager=off -c \
  "SELECT site_id,source_type,source_key,target_country_code,site_url
   FROM jobpush.career_sites WHERE consolidation_key='13-2624428' ORDER BY site_id;"
