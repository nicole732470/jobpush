#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P2_FAST_SOURCE_LIMIT=50 bash "$SCRIPT_DIR/run_due_crawl_p2_fast_structured_wave.sh"
