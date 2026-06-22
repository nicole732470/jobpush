#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "==> migration 027 persistent Google priority overrides"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/027_google_priority_overrides.sql"

echo "==> refresh consolidated effective tiers"
"${PSQL[@]}" -f "$SCRIPT_DIR/refresh/refresh_company_targets_consolidated.sql"

echo "==> sync operational crawl targets"
"${PSQL[@]}" -f "$SCRIPT_DIR/refresh/sync_crawl_targets.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT target.consolidation_key,
          target.canonical_name,
          target.computed_crawl_priority_tier,
          target.crawl_priority_tier AS effective_tier,
          override.reason
   FROM jobpush.company_targets_consolidated target
   JOIN jobpush.crawl_priority_overrides override USING (consolidation_key)
   WHERE target.consolidation_key IN ('google', 'alphabet-google')
   ORDER BY target.canonical_name;"
