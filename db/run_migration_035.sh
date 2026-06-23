#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/035_strata_career_site.sql"
"${PSQL[@]}" -P pager=off -c \
  "SELECT site_id, candidate_rank, site_url, verification_status, source_type, crawl_enabled
   FROM jobpush.career_sites WHERE consolidation_key = '32-0368502' ORDER BY site_id;"
"${PSQL[@]}" -P pager=off -c \
  "SELECT COUNT(*) AS review_queue_rows
   FROM jobpush.career_site_company_review_queue WHERE consolidation_key = '32-0368502';"
"${PSQL[@]}" -P pager=off -c \
  "SELECT consolidation_key, discovery_status FROM jobpush.crawl_targets WHERE consolidation_key = '32-0368502';"
