#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/migrations/130_reject_uber_smartrecruiters_test_site.sql"
"${PSQL[@]}" -P pager=off -c \
  "SELECT site_id, site_url, verification_status, crawl_enabled, crawl_status, review_notes
   FROM jobpush.career_sites WHERE consolidation_key = 'uber' ORDER BY site_id;"
