#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

MAX_BATCHES="${MAX_BATCHES:-40}"
[[ "$MAX_BATCHES" =~ ^[1-9][0-9]*$ ]] || { echo "MAX_BATCHES must be a positive integer" >&2; exit 2; }

due_count() {
  "${PSQL[@]}" -qAt -c "
    SELECT count(*)
    FROM jobpush.crawl_schedule_queue
    WHERE is_due
      AND crawl_status <> 'running'
      AND priority_tier = 'P2'
      AND source_type = 'workday';
  "
}

echo "P2 Workday drain start: due=$(due_count), max_batches=$MAX_BATCHES"

for batch in $(seq 1 "$MAX_BATCHES"); do
  due_before="$(due_count)"
  if [[ "$due_before" -le 0 ]]; then
    echo "No P2 Workday sites due."
    break
  fi

  echo "== batch $batch/$MAX_BATCHES: due_before=$due_before =="
  tmp_log="$(mktemp)"
  if SKIP_POST_CRAWL_TITLE_ML=1 bash "$SCRIPT_DIR/run_due_crawl_p2_workday_10.sh" >"$tmp_log" 2>&1; then
    grep -E '^(Completed|All due-site crawls failed|Some due-site crawls failed)' "$tmp_log" || tail -20 "$tmp_log"
  else
    echo "Batch failed; last log lines:"
    tail -80 "$tmp_log"
    rm -f "$tmp_log"
    exit 1
  fi
  rm -f "$tmp_log"
done

echo "P2 Workday drain end: due=$(due_count)"
