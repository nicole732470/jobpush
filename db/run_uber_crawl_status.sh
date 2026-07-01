#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -P pager=off -c \
  "SELECT site_id, crawl_status, last_error, last_crawled_at, last_success_at
   FROM jobpush.career_sites WHERE site_id=25098;"

"${PSQL[@]}" -P pager=off -c \
  "SELECT run_id, status, error_message, discovered_job_count, finished_at
   FROM jobpush.crawl_runs WHERE site_id=25098 ORDER BY run_id DESC LIMIT 3;"
