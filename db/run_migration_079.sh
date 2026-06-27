#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/migrations/079_supported_structured_candidate_expansion.sql"
"${PSQL[@]}" -P pager=off -c "
SELECT source_type,
       normalized_domain,
       count(*) AS enabled_sites,
       count(DISTINCT consolidation_key) AS companies
FROM jobpush.career_sites
WHERE reviewed_by = 'system:supported-structured-rank2-v1'
GROUP BY source_type, normalized_domain
ORDER BY companies DESC, source_type, normalized_domain;

SELECT priority_tier, source_type, count(*) AS due_sites
FROM jobpush.crawl_schedule_queue
WHERE is_due
GROUP BY priority_tier, source_type
ORDER BY priority_tier, source_type;
"
