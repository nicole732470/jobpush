#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PRIORITY_TIER_FILTER=P2
export SKIP_POST_CRAWL_TITLE_ML="${SKIP_POST_CRAWL_TITLE_ML:-1}"
bash "$SCRIPT_DIR/run_due_crawl_batch.sh" 100
