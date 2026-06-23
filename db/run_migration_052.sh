#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/migrations/052_workbench_verified_precedence.sql"
"${PSQL[@]}" -P pager=off -c \
  "SELECT priority_tier,action_status,count(*) AS companies
   FROM jobpush.career_site_review_workbench
   GROUP BY priority_tier,action_status ORDER BY priority_tier,action_status;
   SELECT review_rank,priority_tier,canonical_name,potential_p0_signal,
          action_status,candidate_1_site_id,candidate_1_url,verified_url
   FROM jobpush.career_site_review_workbench
   ORDER BY review_rank LIMIT 12;"
