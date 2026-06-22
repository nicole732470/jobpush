#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "==> migration 022 crawl_priority_tier"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/022_crawl_priority_tier.sql"

echo "==> refresh consolidated (assign P1/P2 tiers)"
/usr/bin/time -p "${PSQL[@]}" -c '\timing on' \
  -f "$SCRIPT_DIR/refresh/refresh_company_targets_consolidated.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT crawl_priority_tier,
          COUNT(*) AS companies,
          ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_all
   FROM jobpush.company_targets_consolidated
   GROUP BY crawl_priority_tier
   ORDER BY crawl_priority_tier NULLS LAST;"

"${PSQL[@]}" -P pager=off -c \
  "SELECT crawl_priority_tier,
          COUNT(*) AS companies,
          ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_target_role
   FROM jobpush.company_targets_consolidated
   WHERE target_role_score = 1
   GROUP BY crawl_priority_tier
   ORDER BY crawl_priority_tier NULLS LAST;"

"${PSQL[@]}" -P pager=off -c \
  "SELECT priority_score, crawl_priority_tier, COUNT(*) AS companies
   FROM jobpush.company_targets_consolidated
   WHERE crawl_priority_tier IS NOT NULL
   GROUP BY priority_score, crawl_priority_tier
   ORDER BY priority_score DESC;"
