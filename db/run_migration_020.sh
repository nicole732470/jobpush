#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "Dropping jobpush wage-repair staging tables (JobLens public tables unchanged)."
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/020_drop_wage_repair_staging.sql"
