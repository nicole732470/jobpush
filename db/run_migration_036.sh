#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/036_united_airlines_career_site.sql"
"${PSQL[@]}" -P pager=off -c \
  "SELECT site_id, candidate_rank, site_url, verification_status, crawl_enabled
   FROM jobpush.career_sites WHERE consolidation_key = '74-2099724' ORDER BY site_id;"
"${PSQL[@]}" -P pager=off -c \
  "SELECT COUNT(*) FROM jobpush.career_site_company_review_queue WHERE consolidation_key = '74-2099724';"
"${PSQL[@]}" -P pager=off -c \
  "SELECT discovery_status FROM jobpush.crawl_targets WHERE consolidation_key = '74-2099724';"
