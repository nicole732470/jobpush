#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/migrations/064_profile_title_rule_engine.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT classification_status, rule_version, count(*) AS distinct_titles
   FROM jobpush.job_title_labels
   GROUP BY 1,2 ORDER BY 1,2;
   SELECT market_scope, count(*) AS active_postings
   FROM jobpush.job_postings
   WHERE active
   GROUP BY 1 ORDER BY 1;"
