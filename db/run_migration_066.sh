#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/migrations/066_ai_job_title_classifier.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT to_regclass('jobpush.job_title_ai_classifications') AS ai_table;"
