#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIMIT="${SMARTRECRUITERS_LIMIT:-5}"
bash "$SCRIPT_DIR/run_due_crawl_by_source.sh" smartrecruiters "$LIMIT"
