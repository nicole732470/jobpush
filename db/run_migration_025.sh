#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "==> migration 025 career-site manual review"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/025_career_site_manual_review.sql"

"${PSQL[@]}" -P pager=off -c \
  "SELECT discovery_status, COUNT(*) AS companies
   FROM jobpush.crawl_targets
   WHERE priority_score >= 4.5
   GROUP BY discovery_status ORDER BY discovery_status;"

"${PSQL[@]}" -P pager=off -c \
  "SELECT source_type, COUNT(*) AS review_candidates
   FROM jobpush.career_site_review_queue
   GROUP BY source_type ORDER BY review_candidates DESC;"
