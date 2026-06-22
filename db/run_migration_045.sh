#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"
echo "==> migration 045 crawl scope policy"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/045_crawl_scope_policy.sql"
"${PSQL[@]}" -P pager=off -c \
  "SELECT us_scope_ready,count(*) AS sites
   FROM jobpush.crawl_scope_readiness GROUP BY 1 ORDER BY 1 DESC;
   SELECT site_id,source_type,target_country_code,scope_method,us_scope_ready
   FROM jobpush.crawl_scope_readiness
   WHERE site_id IN (38,70,78,111,287,288,292) ORDER BY site_id;"
