#!/usr/bin/env bash
# Persist newly discovered or changed target-job JDs without exporting or emailing.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${JOBPUSH_REFRESH_SINCE:=$(date -u +%FT%TZ)}"
export JOBPUSH_REFRESH_SINCE

# Nightly ingestion is incremental. Historical JD backfills use the dedicated
# batch runner, so one unusually large backlog cannot OOM the daily crawl.
JOBPUSH_EXPORT_SCOPE="${JOBPUSH_JD_INGEST_SCOPE:-new_target_jobs_only}" \
  JOBPUSH_SKIP_EXPORT=1 JOBPUSH_SKIP_EMAIL=1 \
  bash "$SCRIPT_DIR/run_daily_job_export.sh" "$@"
