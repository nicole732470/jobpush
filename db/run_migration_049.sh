#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/migrations/049_manual_job_title_labels.sql"
"${PSQL[@]}" -P pager=off -c \
  "SELECT count(*) AS unresolved_titles FROM jobpush.job_title_review_queue;"
