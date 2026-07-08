#!/usr/bin/env bash
# Reject bad structured candidates, then crawl due sites in background (SSM-safe).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIMIT="${DUE_CRAWL_LIMIT:-${1:-500}}"
LOG_FILE="${DUE_CRAWL_LOG:-/tmp/jobpush-due-crawl-${LIMIT}.log}"
LOCK_FILE="/tmp/jobpush-due-crawl-batch.lock"

echo "=== Reject bad unverified structured candidates ==="
bash "$SCRIPT_DIR/run_reject_bad_structured_candidates.sh"

echo "=== Due crawl batch (limit=$LIMIT) in background ==="
if [[ -f "$LOCK_FILE" ]] && kill -0 "$(cat "$LOCK_FILE")" 2>/dev/null; then
  echo "Due crawl already running (pid=$(cat "$LOCK_FILE")); log=$LOG_FILE"
  exit 0
fi

nohup bash "$SCRIPT_DIR/run_due_crawl_batch.sh" "$LIMIT" >"$LOG_FILE" 2>&1 &
echo $! >"$LOCK_FILE"
echo "Started due crawl pid=$(cat "$LOCK_FILE"); log=$LOG_FILE"
sleep 2
head -n 20 "$LOG_FILE" || true
