#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/migrations/074_generic_html_resolution_cleanup.sql"
"${PSQL[@]}" -P pager=off -c "
SELECT verification_status, source_type, count(*) AS sites, count(DISTINCT consolidation_key) AS companies
FROM jobpush.career_sites
WHERE source_type IN (
    'generic_html', 'jobvite', 'workable', 'paylocity', 'rippling',
    'ultipro', 'trinethire', 'comeet'
)
GROUP BY verification_status, source_type
ORDER BY verification_status, source_type;
"
