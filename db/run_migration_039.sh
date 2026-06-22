#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "==> migration 039 market scope and adapter pilots"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/039_market_scope_and_adapter_pilots.sql"
"${PSQL[@]}" -P pager=off -c \
  "SELECT market_scope, count(*) FROM jobpush.job_postings GROUP BY 1 ORDER BY 1;
   SELECT site_id, source_type, target_country_code
   FROM jobpush.career_sites WHERE site_id IN (70, 78, 288) ORDER BY site_id;"
