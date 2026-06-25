#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/migrations/071_tavily_enrichment_visibility.sql"
"${PSQL[@]}" -P pager=off -c "
SELECT enrichment_state, count(*) FROM jobpush.company_priority_enrichment_workbench
GROUP BY 1 ORDER BY 1;
SELECT canonical_name, external_industry, external_headquarters_city,
       employee_count_min, founded_year, ownership_type
FROM jobpush.company_priority_enrichment_workbench
WHERE enrichment_state = 'structured_unreviewed'
ORDER BY enrichment_researched_at DESC;
"
