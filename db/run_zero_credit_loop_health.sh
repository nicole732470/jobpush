#!/usr/bin/env bash
set -euo pipefail

echo "==> zero-credit loop processes"
pgrep -af "run_zero_credit_site_processing_loop|run_due_crawl_batch|run_structured_adapter|crawl_.*\\.py|resolve_generic_ats" || true

echo
echo "==> zero-credit loop log tail"
tail -160 /opt/jobpush/logs/zero_credit_site_processing.log || true

echo
echo "==> current site processing status"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/run_site_processing_status.sh"
