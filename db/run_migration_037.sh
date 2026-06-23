#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/037_google_career_site.sql"
"${PSQL[@]}" -P pager=off -c \
  "SELECT consolidation_key, site_id, site_url, verification_status, crawl_enabled
   FROM jobpush.career_sites
   WHERE consolidation_key IN ('google', 'alphabet-google')
   ORDER BY consolidation_key;"
"${PSQL[@]}" -P pager=off -c \
  "SELECT consolidation_key, discovery_status, priority_tier
   FROM jobpush.crawl_targets
   WHERE consolidation_key IN ('google', 'alphabet-google');"
