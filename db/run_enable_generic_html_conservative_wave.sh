#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

LIMIT="${GENERIC_HTML_ENABLE_LIMIT:-500}"
MIN_SCORE="${GENERIC_HTML_MIN_SCORE:-65}"

[[ "$LIMIT" =~ ^[1-9][0-9]*$ ]] || { echo "GENERIC_HTML_ENABLE_LIMIT must be a positive integer" >&2; exit 2; }

"${PSQL[@]}" \
  -v limit="$LIMIT" \
  -v min_candidate_score="$MIN_SCORE" \
  -v ON_ERROR_STOP=1 \
  -f "$SCRIPT_DIR/ops/enable_generic_html_conservative_wave.sql"

"${PSQL[@]}" -P pager=off <<'SQL'
SELECT priority_tier, source_type, count(*) AS due_sites
FROM jobpush.crawl_schedule_queue
WHERE is_due
GROUP BY 1, 2
ORDER BY 1, 2;
SQL
