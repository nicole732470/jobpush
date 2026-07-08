#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

echo "=== Step 1: normalize UltiPro + reject Phenom CDN ==="
bash "$SCRIPT_DIR/run_normalize_ultipro_and_reject_phenom_cdn.sh"

echo "=== Step 2: enable UltiPro parser + pilot sites ==="
bash "$SCRIPT_DIR/run_migration_153.sh"

echo "=== Step 3: crawl enabled UltiPro pilot sites ==="
SITE_ROWS=$("${PSQL[@]}" -qAt -c "
  SELECT site_id
  FROM jobpush.career_sites
  WHERE reviewed_by = 'system:ultipro-parser-pilot-v1'
    AND crawl_enabled
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
bash "$SCRIPT_DIR/run_ultipro_phenom_parser_priority.sh"
