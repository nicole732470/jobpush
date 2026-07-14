#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

health_run_id="$("${PSQL[@]}" -qAt -c "INSERT INTO jobpush.crawl_health_runs DEFAULT VALUES RETURNING health_run_id;")"
trap '"${PSQL[@]}" -q -c "UPDATE jobpush.crawl_health_runs SET status='"'"'failed'"'"',finished_at=now() WHERE health_run_id=$health_run_id" || true' ERR
"${PSQL[@]}" -v ON_ERROR_STOP=1 -v health_run_id="$health_run_id" \
  -f "$SCRIPT_DIR/ops/run_daily_crawl_health.sql"
trap - ERR
