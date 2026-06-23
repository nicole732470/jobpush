#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "==> migration 053 Accenture career site + P0"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/053_accenture_career_site_and_p0.sql"
"${PSQL[@]}" -f "$SCRIPT_DIR/refresh/refresh_company_targets_consolidated.sql"
"${PSQL[@]}" -f "$SCRIPT_DIR/refresh/sync_crawl_targets.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT consolidation_key, site_id, site_url, verification_status,
          crawl_enabled, target_country_code, scope_method
   FROM jobpush.career_sites WHERE consolidation_key = 'accenture' ORDER BY site_id;"

"${PSQL[@]}" -P pager=off -c \
  "SELECT consolidation_key, canonical_name, priority_tier, priority_source, discovery_status
   FROM jobpush.crawl_targets WHERE consolidation_key = 'accenture';"

"${PSQL[@]}" -P pager=off -c \
  "SELECT consolidation_key, priority_tier, action_status, verified_url
   FROM jobpush.career_site_review_workbench WHERE consolidation_key = 'accenture';"
