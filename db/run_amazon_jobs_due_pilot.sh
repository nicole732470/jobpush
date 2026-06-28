#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIMIT="${AMAZON_JOBS_LIMIT:-1}"
bash "$SCRIPT_DIR/run_due_crawl_by_source.sh" amazon_jobs "$LIMIT"
