#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"
echo "==> migration 047 repair HERE scoped closure"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/047_repair_here_scope_closure.sql"
"${PSQL[@]}" -P pager=off -c \
  "SELECT market_scope,active,count(*) AS postings
   FROM jobpush.job_postings WHERE site_id=78 GROUP BY 1,2 ORDER BY 1,2;"
