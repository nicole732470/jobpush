#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIMIT="${DUE_CRAWL_LIMIT:-20}"
SOURCE_TYPE_FILTER=ultipro bash "$SCRIPT_DIR/run_due_crawl_batch.sh" "$LIMIT"
