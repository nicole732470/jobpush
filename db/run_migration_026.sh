#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "==> migration 026 persistent crawl-priority overrides"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/026_crawl_priority_overrides.sql"

echo "==> refresh consolidated effective tiers"
"${PSQL[@]}" -f "$SCRIPT_DIR/refresh/refresh_company_targets_consolidated.sql"

echo "==> sync operational crawl targets"
"${PSQL[@]}" -f "$SCRIPT_DIR/refresh/sync_crawl_targets.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT target.canonical_name,
          target.priority_score,
          target.computed_crawl_priority_tier,
          target.crawl_priority_tier AS effective_tier,
          override.reason
   FROM jobpush.company_targets_consolidated target
   JOIN jobpush.crawl_priority_overrides override USING (consolidation_key)
   WHERE override.active
   ORDER BY target.canonical_name;"

"${PSQL[@]}" -P pager=off -c \
  "SELECT crawl_priority_tier, COUNT(*) AS companies,
          ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_all
   FROM jobpush.company_targets_consolidated
   GROUP BY crawl_priority_tier
   ORDER BY crawl_priority_tier NULLS LAST;"
