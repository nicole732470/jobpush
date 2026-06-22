#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "==> migration 038 crawl execution tables"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/038_crawl_execution.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT table_name
   FROM information_schema.tables
   WHERE table_schema = 'jobpush'
     AND table_name IN ('crawl_batches', 'crawl_batch_targets', 'crawl_runs',
                        'job_postings', 'job_title_labels')
   ORDER BY table_name;"
