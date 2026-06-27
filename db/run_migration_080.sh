#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/migrations/080_senior_sde_title_exclusion.sql"
"${PSQL[@]}" -P pager=off -c "
SELECT classification_status,
       COALESCE(decision_reason, '') AS decision_reason,
       COUNT(*) AS titles
FROM jobpush.job_title_labels
WHERE decision_reason ILIKE '%profile_avoid_senior_sde_track%'
GROUP BY classification_status, COALESCE(decision_reason, '')
ORDER BY titles DESC;

SELECT normalized_title, classification_status, rule_version, decision_reason
FROM jobpush.job_title_labels
WHERE decision_reason ILIKE '%profile_avoid_senior_sde_track%'
ORDER BY normalized_title
LIMIT 40;
"
