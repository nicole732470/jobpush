#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -P pager=off <<'SQL'
UPDATE jobpush.career_sites
SET crawl_status = 'pending',
    next_crawl_at = now(),
    last_error = NULL,
    updated_at = now()
WHERE site_id = 25098;
SQL

export SITE_ID_FILTER=25098
bash "$SCRIPT_DIR/run_due_crawl_batch.sh" 1

"${PSQL[@]}" -P pager=off -c \
  "SELECT count(*) AS uber_dashboard_jobs
   FROM jobpush.dashboard_jobs
   WHERE consolidation_key = 'uber';"

"${PSQL[@]}" -P pager=off -c \
  "SELECT site_id, crawl_status, last_error, last_success_at
   FROM jobpush.career_sites WHERE site_id = 25098;"

"${PSQL[@]}" -P pager=off -c \
  "SELECT run_id, status, error_message, parsed_job_count, finished_at
   FROM jobpush.crawl_runs WHERE site_id = 25098 ORDER BY run_id DESC LIMIT 1;"
