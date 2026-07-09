#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES=(
  greenhouse smartrecruiters ashby lever paylocity oracle_cloud workable jobvite
  applicantpro dover jobscore catsone trakstar breezy applytojob eightfold
  amazon_jobs cognizant_jobs phenom
)
LIMIT="${FAST_SOURCE_LIMIT:-5}"
TIERS="${FAST_PRIORITY_TIERS:-P0,P1,P2,P3}"
LOG_DIR="$(mktemp -d /tmp/jobpush-fast-wave.XXXXXX)"
trap 'rm -rf "$LOG_DIR"' EXIT

pids=()
for source_type in "${SOURCES[@]}"; do
  (
    echo "=== fast due crawl source_type=$source_type limit=$LIMIT tiers=$TIERS ==="
    PRIORITY_TIER_FILTER="$TIERS" \
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

bash "$SCRIPT_DIR/run_post_crawl_title_classification.sh"
