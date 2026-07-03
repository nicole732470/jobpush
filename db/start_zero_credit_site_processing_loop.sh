#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="${LOG_FILE:-$REPO_DIR/logs/zero_credit_site_processing.log}"

if pgrep -f "run_zero_credit_site_processing_loop\\.sh" >/dev/null; then
  echo "zero-credit site processing loop is already running."
  pgrep -af "run_zero_credit_site_processing_loop\\.sh" || true
  exit 0
fi

mkdir -p "$(dirname "$LOG_FILE")"

export MAX_CYCLES="${MAX_CYCLES:-48}"
export CRAWL_BATCH_SIZE="${CRAWL_BATCH_SIZE:-300}"
export GENERIC_BATCH_SIZE="${GENERIC_BATCH_SIZE:-1000}"
export WAIT_SECONDS="${WAIT_SECONDS:-60}"

if command -v setsid >/dev/null 2>&1; then
  setsid bash "$SCRIPT_DIR/run_zero_credit_site_processing_loop.sh" \
    >> "$LOG_FILE" 2>&1 < /dev/null &
else
  nohup bash "$SCRIPT_DIR/run_zero_credit_site_processing_loop.sh" \
    >> "$LOG_FILE" 2>&1 < /dev/null &
fi

echo "started zero-credit site processing loop pid=$! log=$LOG_FILE"
