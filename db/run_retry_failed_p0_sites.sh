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
  AND target.priority_tier = 'P0'
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.crawl_status = 'failed';

SELECT target.canonical_name, site.source_type, site.crawl_status, site.next_crawl_at
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier = 'P0'
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
ORDER BY target.canonical_name, site.source_type;
SQL
