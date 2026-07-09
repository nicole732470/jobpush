#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

SITE_ID="$("${PSQL[@]}" -qAt -c "
  SELECT site_id
  FROM jobpush.career_sites
  WHERE consolidation_key='74-2099724'
    AND site_url='https://careers.united.com/us/en/search-results'
    AND source_type='phenom'
  ORDER BY site_id DESC
  LIMIT 1;
")"

if [[ -z "$SITE_ID" ]]; then
  echo "United career site not found" >&2
  exit 1
fi

"${PSQL[@]}" -q -c "
  UPDATE jobpush.career_sites
  SET next_crawl_at=now(), crawl_status='pending', last_error=NULL, updated_at=now()
  WHERE site_id=$SITE_ID;
"

SITE_ID_FILTER="$SITE_ID" bash "$SCRIPT_DIR/run_due_crawl_batch.sh" 1
