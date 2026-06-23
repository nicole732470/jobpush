#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/migrations/048_crawl_schedule_and_health.sql"
"${PSQL[@]}" -P pager=off -c \
  "SELECT priority_tier, source_type, count(*) AS sites,
          count(*) FILTER (WHERE is_due) AS due
   FROM jobpush.crawl_schedule_queue
   GROUP BY priority_tier, source_type
   ORDER BY priority_tier, source_type;
   SELECT * FROM jobpush.crawl_adapter_health ORDER BY source_type;
   SELECT * FROM jobpush.crawl_site_alerts ORDER BY priority_tier, canonical_name;"
