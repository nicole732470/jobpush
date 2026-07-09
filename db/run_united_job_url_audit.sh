#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -P pager=off <<'SQL'
SELECT
    posting.title,
    posting.active,
    posting.closed_at,
    posting.job_url,
    posting.last_seen_at
FROM jobpush.job_postings posting
JOIN jobpush.career_sites site USING (site_id)
WHERE site.consolidation_key = '74-2099724'
  AND posting.external_job_id ILIKE '%WHQ00026413%'
ORDER BY posting.last_seen_at DESC
LIMIT 5;
SQL
