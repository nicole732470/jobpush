#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"
echo "==> migration 046 exact SOC title labels"
"${PSQL[@]}" -f "$SCRIPT_DIR/migrations/046_exact_soc_title_labels.sql"
"${PSQL[@]}" -P pager=off -c \
  "SELECT classification_status,labeled_by,count(*) AS distinct_titles
   FROM jobpush.job_title_labels GROUP BY 1,2 ORDER BY 1,2;
   SELECT label.classification_status,count(*) AS active_us_postings
   FROM jobpush.job_postings_us posting
   JOIN jobpush.job_title_labels label USING(normalized_title)
   GROUP BY 1 ORDER BY 1;
   SELECT count(*) AS titles_needing_review FROM jobpush.job_title_review_queue;"
