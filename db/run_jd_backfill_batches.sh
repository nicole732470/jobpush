#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPORT_DATE="${1:-$(TZ=America/Chicago date +%F)}"
BATCH_SIZE="${JOBPUSH_JD_BATCH_SIZE:-50}"
WORKERS="${JOBPUSH_JD_WORKERS:-4}"

while true; do
  if JOBPUSH_CRAWL_COMPLETE=1 JOBPUSH_EXPORT_SCOPE=all_active_target \
       JOBPUSH_JD_LIMIT="$BATCH_SIZE" JOBPUSH_JD_WORKERS="$WORKERS" JOBPUSH_SKIP_EXPORT=1 \
       bash "$SCRIPT_DIR/run_daily_job_export.sh" "$EXPORT_DATE"; then
    :
  else
    code=$?
    (( code == 10 )) && break
    exit "$code"
  fi
done

JOBPUSH_CRAWL_COMPLETE=1 JOBPUSH_EXPORT_SCOPE=all_active_target JOBPUSH_JD_LIMIT=1 \
  bash "$SCRIPT_DIR/run_daily_job_export.sh" "$EXPORT_DATE"
