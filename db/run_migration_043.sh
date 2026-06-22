#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"
echo "==> migration 043 StackAdapt US Greenhouse site"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/043_stackadapt_greenhouse_site.sql"
"${PSQL[@]}" -P pager=off -c \
  "SELECT site_id,site_url,source_type,verification_status,target_country_code,crawl_enabled
   FROM jobpush.career_sites WHERE consolidation_key='30-1005380' ORDER BY site_id;"
