#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "$SCRIPT_DIR/run_migration_133.sh"
bash "$SCRIPT_DIR/run_migration_137.sh"
bash "$SCRIPT_DIR/run_migration_138.sh"
bash "$SCRIPT_DIR/run_migration_139.sh"

LIMIT="${1:-120}"
bash "$SCRIPT_DIR/run_due_crawl_batch.sh" "$LIMIT"
