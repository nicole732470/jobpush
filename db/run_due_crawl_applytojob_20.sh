#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIMIT="${1:-20}"
bash "$SCRIPT_DIR/run_due_crawl_by_source.sh" applytojob "$LIMIT"
