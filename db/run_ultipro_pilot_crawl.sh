#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "=== Crawl enabled UltiPro pilot sites ==="
SITE_ROWS=$("${PSQL[@]}" -qAt -c "
  SELECT site_id
  FROM jobpush.career_sites
  WHERE reviewed_by = 'system:ultipro-parser-pilot-v1'
    AND crawl_enabled
    AND COALESCE(last_success_at, to_timestamp(0)) < reviewed_at
  ORDER BY site_id;
")
count=0
failures=0
while IFS= read -r site_id; do
  [[ -n "$site_id" ]] || continue
  count=$((count + 1))
  echo "==> UltiPro pilot site_id=$site_id"
  if SITE_ID_FILTER="$site_id" bash "$SCRIPT_DIR/run_due_crawl_batch.sh" 1; then
    :
  else
    failures=$((failures + 1))
  fi
done <<< "$SITE_ROWS"

echo "UltiPro pilot crawl complete: attempted=$count failures=$failures"
