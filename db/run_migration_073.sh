#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/migrations/073_drop_tavily_company_profile_enrichment.sql"
"${PSQL[@]}" -P pager=off -c "
SELECT to_regclass('jobpush.company_priority_enrichment_workbench') AS enrichment_workbench,
       to_regclass('jobpush.company_external_enrichment') AS external_enrichment;
"
