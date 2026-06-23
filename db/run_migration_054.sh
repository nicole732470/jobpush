#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/054_optime_tech_career_site.sql"
"${PSQL[@]}" -P pager=off -c \
  "SELECT site_id, site_url, verification_status, crawl_enabled, scope_method
   FROM jobpush.career_sites WHERE consolidation_key = '20-3471277' ORDER BY site_id;"
"${PSQL[@]}" -P pager=off -c \
  "SELECT consolidation_key, action_status, verified_url
   FROM jobpush.career_site_review_workbench WHERE consolidation_key = '20-3471277';"
