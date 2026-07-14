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
echo "Nightly crawl drain started at $(date -u +%FT%TZ); due_sites=$initial_due batch_size=$BATCH_SIZE"
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

if (( completed_batches > 0 )); then
  bash "$SCRIPT_DIR/run_post_crawl_title_classification.sh"
fi

remaining="$(due_count)"
if (( completed_batches >= MAX_BATCHES && remaining > 0 )); then
  echo "Daily export withheld: batch limit reached with $remaining due sites still queued." >&2
  exit 1
fi
(( remaining == 0 )) || echo "Crawl attempted all queued sites; $remaining failed/unsupported sites remain due for recovery."

echo "==> daily crawl health analysis and safe recovery"
bash "$SCRIPT_DIR/run_daily_crawl_health.sh"

echo "==> rediscover stale Greenhouse/Ashby/Lever boards (daily capped)"
bash "$SCRIPT_DIR/run_rediscover_failed_ats.sh" "${ATS_REDISCOVERY_LIMIT:-25}"

echo "==> export today's newly crawled target jobs and email JSON"
JOBPUSH_CRAWL_COMPLETE=1 bash "$SCRIPT_DIR/run_daily_job_export.sh"

echo "Nightly crawl drain completed at $(date -u +%FT%TZ); batches=$completed_batches remaining_due=$remaining"
