#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

RUN_ID="${1:-}"
if [[ -z "$RUN_ID" ]]; then
  RUN_ID=$("${PSQL[@]}" -qAt -c "
    SELECT run_id
    FROM jobpush.career_site_discovery_result_stage
    GROUP BY run_id
    ORDER BY max(consolidation_key) DESC
    LIMIT 1;
  ")
fi

[[ -n "$RUN_ID" ]] || { echo "No staged discovery run found." >&2; exit 1; }

"${PSQL[@]}" -v run_id="$RUN_ID" -v cohort="effective-tier-p0-p1-score-expansion" \
  -f "$SCRIPT_DIR/load/finalize_career_site_discovery.sql"

"${PSQL[@]}" -P pager=off -c "
SELECT run_id, cohort, target_count, candidate_count, error_count, estimated_credits, status
FROM jobpush.career_site_discovery_runs
WHERE run_id = '$RUN_ID';
SELECT priority_tier, discovery_status, count(*) AS companies
FROM jobpush.crawl_targets
WHERE enabled AND priority_tier IN ('P0','P1')
GROUP BY 1,2
ORDER BY 1,2;
"
