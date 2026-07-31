#!/usr/bin/env bash
# Drain the due-site queue without idle gaps, then classify and refresh once.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

BATCH_SIZE="${CRAWL_BATCH_SIZE:-100}"
MAX_BATCHES="${MAX_CRAWL_BATCHES:-100}"
[[ "$BATCH_SIZE" =~ ^[1-9][0-9]*$ ]] || { echo "CRAWL_BATCH_SIZE must be positive" >&2; exit 2; }
[[ "$MAX_BATCHES" =~ ^[1-9][0-9]*$ ]] || { echo "MAX_CRAWL_BATCHES must be positive" >&2; exit 2; }

due_count() {
  "${PSQL[@]}" -qAt -c "
    SELECT count(*) FROM jobpush.crawl_schedule_queue
    WHERE is_due AND crawl_status <> 'running';
  "
}

initial_due="$(due_count)"
RUN_STARTED_AT="$(date -u +%FT%TZ)"
echo "Nightly crawl drain started at $RUN_STARTED_AT; due_sites=$initial_due batch_size=$BATCH_SIZE"
(( initial_due > 0 )) || echo "No sites are due; continuing to the post-crawl export check."

completed_batches=0
for batch_number in $(seq 1 "$MAX_BATCHES"); do
  before="$(due_count)"
  (( before > 0 )) || break
  current_size="$BATCH_SIZE"
  (( before < current_size )) && current_size="$before"

  echo "==> batch $batch_number/$MAX_BATCHES size=$current_size due_before=$before"
  SKIP_POST_CRAWL_TITLE_ML=1 bash "$SCRIPT_DIR/run_due_crawl_batch.sh" "$current_size"
  completed_batches=$batch_number

  after="$(due_count)"
  echo "<== batch $batch_number complete due_after=$after"
  if (( after >= before )); then
    echo "Due queue made no progress; stopping to avoid a tight retry loop." >&2
    break
  fi
done

remaining="$(due_count)"
if (( remaining > 0 )); then
  echo "Continuing with a partial daily export; $remaining failed sites remain queued for retry." >&2
fi

# The crawl-complete boundary is the queue snapshot immediately after the
# drain. Sites that become due during the slower classification/export phase
# belong to the next scheduled run and must not invalidate this one.
if (( completed_batches > 0 )); then
  JOBPUSH_REFRESH_SINCE="$RUN_STARTED_AT" bash "$SCRIPT_DIR/run_post_crawl_title_classification.sh"
fi

echo "==> daily crawl health analysis and safe recovery"
bash "$SCRIPT_DIR/run_daily_crawl_health.sh"

echo "==> rediscover stale Greenhouse/Ashby/Lever boards (daily capped)"
bash "$SCRIPT_DIR/run_rediscover_failed_ats.sh" "${ATS_REDISCOVERY_LIMIT:-25}"

echo "==> persist complete JDs for today's newly crawled target jobs"
# Keep raw JD HTML bounded in memory. A normal day completes in one pass;
# backlog JDs remain for the dedicated backfill runner instead of OOMing this job.
JD_BATCH_SIZE="${JOBPUSH_JD_BATCH_SIZE:-250}"
[[ "$JD_BATCH_SIZE" =~ ^[1-9][0-9]*$ ]] || { echo "JOBPUSH_JD_BATCH_SIZE must be positive" >&2; exit 2; }
while :; do
  jd_output="$(JOBPUSH_REFRESH_SINCE="$RUN_STARTED_AT" JOBPUSH_CRAWL_COMPLETE=1 \
    JOBPUSH_JD_WORKERS="${JOBPUSH_JD_WORKERS:-4}" JOBPUSH_JD_LIMIT="$JD_BATCH_SIZE" \
    bash "$SCRIPT_DIR/run_daily_jd_ingestion.sh")"
  printf '%s\n' "$jd_output"
  jd_processed="$(sed -n 's/.*processed=\([0-9][0-9]*\).*/\1/p' <<<"$jd_output" | tail -1)"
  [[ "$jd_processed" =~ ^[0-9]+$ ]] || { echo "Could not read JD batch result" >&2; exit 1; }
  (( jd_processed < JD_BATCH_SIZE )) && break
done

echo "==> optionally export today's target jobs; email is opt-in"
if [[ "${JOBPUSH_SKIP_DAILY_EXPORT:-0}" == "1" ]]; then
  echo "Daily JSON export skipped; JD records are already persisted."
else
  SKIP_EMAIL=1
  [[ "${JOBPUSH_SEND_DAILY_EMAIL:-0}" == "1" ]] && SKIP_EMAIL=0
  JOBPUSH_REFRESH_SINCE="$RUN_STARTED_AT" JOBPUSH_CRAWL_COMPLETE=1 \
    JOBPUSH_SKIP_JD_FETCH=1 JOBPUSH_SKIP_EMAIL="$SKIP_EMAIL" \
    bash "$SCRIPT_DIR/run_daily_job_export.sh"
fi

echo "Nightly crawl drain completed at $(date -u +%FT%TZ); batches=$completed_batches remaining_due=$remaining"
