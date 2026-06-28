#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STALE_MINUTES=1 bash "$SCRIPT_DIR/run_mark_stale_running_crawls_failed.sh"
