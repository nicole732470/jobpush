#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$SCRIPT_DIR/run_due_crawl_by_source.sh" google_jobs 1
bash "$SCRIPT_DIR/run_due_crawl_by_source.sh" cognizant_jobs 1
bash "$SCRIPT_DIR/run_due_crawl_by_source.sh" eightfold 1
