#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "==> migration 029 HERE priority and career site"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/029_here_priority_and_career_site.sql"
"${PSQL[@]}" -f "$SCRIPT_DIR/refresh/refresh_company_targets_consolidated.sql"
"${PSQL[@]}" -f "$SCRIPT_DIR/refresh/sync_crawl_targets.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT target.canonical_name,
          target.priority_score,
          target.computed_crawl_priority_tier,
          target.crawl_priority_tier AS effective_tier,
          queue.priority_source,
          queue.discovery_status
   FROM jobpush.company_targets_consolidated target
   JOIN jobpush.crawl_targets queue USING (consolidation_key)
   WHERE target.consolidation_key = '77-0080465';"

"${PSQL[@]}" -P pager=off -c \
  "SELECT site_id, site_url, source_type, verification_status, crawl_enabled
   FROM jobpush.career_sites
   WHERE consolidation_key = '77-0080465'
   ORDER BY site_id;"
