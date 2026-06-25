#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/migrations/070_executive_only_small_sponsor_exclusion.sql"

bash "$SCRIPT_DIR/refresh/run_refresh_pipeline.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -P pager=off -c "
SELECT
    count(*) FILTER (WHERE executive_only_excluded) AS excluded_companies,
    count(*) FILTER (WHERE executive_only_excluded AND priority_score <> 0) AS nonzero_errors,
    count(*) FILTER (WHERE executive_only_excluded AND crawl_priority_tier IS NOT NULL) AS tier_errors
FROM jobpush.company_targets_consolidated;
SELECT priority_tier, count(*) AS enabled_companies
FROM jobpush.crawl_targets WHERE enabled GROUP BY 1 ORDER BY 1;
"
