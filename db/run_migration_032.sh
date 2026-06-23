#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "==> migration 032 JPMorgan Oracle HCM career site"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/032_jpmorgan_career_site.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT site_id, site_url, source_type, verification_status, crawl_enabled
   FROM jobpush.career_sites
   WHERE consolidation_key = '13-2624428'
   ORDER BY site_id;"

"${PSQL[@]}" -P pager=off -c \
  "SELECT consolidation_key, canonical_name, discovery_status
   FROM jobpush.crawl_targets
   WHERE consolidation_key = '13-2624428';"
