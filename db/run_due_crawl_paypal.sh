#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

SITE_ID="$("${PSQL[@]}" -qAt -c "
  SELECT site_id
  FROM jobpush.career_sites
  WHERE consolidation_key='77-0510487'
    AND site_url='https://paypal.eightfold.ai/careers?start=0&location=United+States&pid=274917452620&sort_by=distance&filter_include_remote=1'
  ORDER BY site_id DESC
  LIMIT 1;
")"

if [[ -z "$SITE_ID" ]]; then
  echo "PayPal career site not found" >&2
  exit 1
fi

SITE_ID_FILTER="$SITE_ID" SKIP_POST_CRAWL_TITLE_ML=1 bash "$SCRIPT_DIR/run_due_crawl_batch.sh" 1
