#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES=(greenhouse smartrecruiters ashby lever paylocity oracle_cloud workable jobvite applicantpro)
LIMIT="${P2_FAST_SOURCE_LIMIT:-10}"
LOG_DIR="$(mktemp -d /tmp/jobpush-p2-fast-wave.XXXXXX)"
trap 'rm -rf "$LOG_DIR"' EXIT

pids=()
for source_type in "${SOURCES[@]}"; do
  (
    echo "=== P2 fast due crawl source_type=$source_type limit=$LIMIT ==="
    PRIORITY_TIER_FILTER=P2 \
      SOURCE_TYPE_FILTER="$source_type" \
      SKIP_POST_CRAWL_TITLE_ML=1 \
      bash "$SCRIPT_DIR/run_due_crawl_batch.sh" "$LIMIT"
  ) > "$LOG_DIR/$source_type.log" 2>&1 &
  pids+=("$!:$source_type")
done

failures=0
for item in "${pids[@]}"; do
  pid="${item%%:*}"
  source_type="${item#*:}"
  if ! wait "$pid"; then
    failures=$((failures + 1))
  fi
  cat "$LOG_DIR/$source_type.log"
done

if [[ "$failures" -gt 0 ]]; then
  echo "$failures source batches had failures; details are recorded in crawl_runs and career_sites." >&2
fi
