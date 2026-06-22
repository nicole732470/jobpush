#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "==> migration 019 employer_filing_stats"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/019_employer_filing_stats.sql"

echo "==> initial employer_filing_stats refresh"
/usr/bin/time -p "${PSQL[@]}" -c '\timing on' \
  -f "$SCRIPT_DIR/refresh/refresh_employer_filing_stats.sql"

echo "==> refresh consolidated crawl queue"
/usr/bin/time -p "${PSQL[@]}" -c '\timing on' \
  -f "$SCRIPT_DIR/refresh/refresh_company_targets_consolidated.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT COUNT(*) AS fein_stats_rows,
          pg_size_pretty(pg_total_relation_size('jobpush.employer_filing_stats'))
              AS employer_filing_stats_size
   FROM jobpush.employer_filing_stats;"

"${PSQL[@]}" -P pager=off -c \
  "SELECT canonical_name, lca_count, priority_score
   FROM jobpush.company_targets_consolidated
   WHERE is_merged_group
   ORDER BY priority_score DESC, lca_count DESC
   LIMIT 8;"
