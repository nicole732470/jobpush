#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/056_the_occ_priority_override.sql"
"${PSQL[@]}" -f "$SCRIPT_DIR/refresh/refresh_company_targets_consolidated.sql"
"${PSQL[@]}" -f "$SCRIPT_DIR/refresh/sync_crawl_targets.sql"
"${PSQL[@]}" -P pager=off -c \
  "SELECT consolidation_key, canonical_name, priority_tier, priority_source, priority_score, discovery_status
   FROM jobpush.crawl_targets WHERE consolidation_key = '36-2756407';"
