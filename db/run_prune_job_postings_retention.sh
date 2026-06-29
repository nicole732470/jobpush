#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
APPLY_RETENTION_DELETE="${APPLY_RETENTION_DELETE:-false}"
"${PSQL[@]}" -v ON_ERROR_STOP=1 -v apply_delete="$APPLY_RETENTION_DELETE" \
  -f "$SCRIPT_DIR/ops/prune_job_postings_retention.sql"
