#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LIMIT="${COST_SAFE_CRAWL_LIMIT:-500}"

[[ "$LIMIT" =~ ^[1-9][0-9]*$ ]] || { echo "COST_SAFE_CRAWL_LIMIT must be positive" >&2; exit 2; }

cd "$REPO_DIR"

systemctl disable --now jobpush-crawl.timer jobpush-crawl.service 2>/dev/null || true
systemctl stop jobpush-dashboard.service 2>/dev/null || true
bash "$SCRIPT_DIR/run_stop_zero_credit_site_processing_loop.sh" || true

echo "==> apply structured ATS auto-trust"
bash "$SCRIPT_DIR/run_apply_career_site_auto_trust.sh"

echo "==> run cost-safe due crawl batch limit=$LIMIT"
bash "$SCRIPT_DIR/run_due_crawl_batch.sh" "$LIMIT"

echo "==> cost-safe site processing status"
bash "$SCRIPT_DIR/run_site_processing_status.sh"
