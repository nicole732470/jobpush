#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -v ON_ERROR_STOP=1 <<'SQL'
UPDATE jobpush.career_sites site
SET crawl_status = 'pending',
    next_crawl_at = now(),
    last_error = NULL,
    updated_at = now()
FROM jobpush.crawl_targets target
WHERE target.consolidation_key = site.consolidation_key
  AND target.enabled
  AND target.priority_tier = 'P2'
  AND site.source_type = 'icims'
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.crawl_status = 'failed';
SQL
PRIORITY_TIER_FILTER=P2 \
  SOURCE_TYPE_FILTER=icims \
  SKIP_POST_CRAWL_TITLE_ML=1 \
  ICIMS_CRAWL_TIMEOUT=30 \
  bash "$SCRIPT_DIR/run_due_crawl_batch.sh" 5 || true
