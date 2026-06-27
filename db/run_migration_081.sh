#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/migrations/081_profile_title_rules_20260627_metadata.sql"
"${PSQL[@]}" -P pager=off -c "
SELECT classification_status,
       COALESCE(decision_reason, '') AS decision_reason,
       COUNT(*) AS titles
FROM jobpush.job_title_labels
WHERE decision_reason ILIKE '%profile_avoid_senior_sde_track%'
GROUP BY classification_status, COALESCE(decision_reason, '')
ORDER BY titles DESC;
"
