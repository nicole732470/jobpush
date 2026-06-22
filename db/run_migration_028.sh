#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "==> migration 028 Baker Hughes priority override"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/028_baker_hughes_priority_override.sql"
"${PSQL[@]}" -f "$SCRIPT_DIR/refresh/refresh_company_targets_consolidated.sql"
"${PSQL[@]}" -f "$SCRIPT_DIR/refresh/sync_crawl_targets.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT target.canonical_name,
          target.priority_score,
          target.computed_crawl_priority_tier,
          target.crawl_priority_tier AS effective_tier,
          override.reason
   FROM jobpush.company_targets_consolidated target
   JOIN jobpush.crawl_priority_overrides override USING (consolidation_key)
   WHERE target.consolidation_key = '81-4403168';"
