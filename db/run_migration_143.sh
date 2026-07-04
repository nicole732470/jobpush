#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/migrations/143_allow_p3_crawl_batches.sql"
"${PSQL[@]}" -P pager=off -c "
SELECT conname, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'jobpush.crawl_batches'::regclass
  AND conname = 'crawl_batches_tier_check';
"
