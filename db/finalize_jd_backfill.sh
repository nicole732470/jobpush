#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
while systemctl is-active --quiet jobpush-jd-backfill.service; do sleep 30; done

cd "$SCRIPT_DIR/.."
git pull --ff-only origin main
source "$SCRIPT_DIR/lib/connect_rds.sh"
status="$("${PSQL[@]}" -qAt -c "SELECT COALESCE(email_status,'') FROM jobpush.daily_job_exports WHERE export_date='2026-07-14';")"
if [[ "$status" != "sent" ]]; then
  JOBPUSH_CRAWL_COMPLETE=1 JOBPUSH_EXPORT_SCOPE=all_active_target JOBPUSH_JD_LIMIT=1 \
    bash "$SCRIPT_DIR/run_daily_job_export.sh" 2026-07-14
fi
