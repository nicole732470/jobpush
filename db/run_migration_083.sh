#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/migrations/083_supported_structured_rank3_expansion.sql"
"${PSQL[@]}" -P pager=off -c "
SELECT source_type,
       normalized_domain,
       count(*) AS enabled_sites,
       count(DISTINCT consolidation_key) AS companies
FROM jobpush.career_sites
WHERE reviewed_by = 'system:supported-structured-rank3-v1'
GROUP BY source_type, normalized_domain
ORDER BY companies DESC, source_type, normalized_domain;

SELECT priority_tier, source_type,
       count(*) FILTER (WHERE is_due) AS due_sites,
       count(*) AS schedulable_sites
FROM jobpush.crawl_schedule_queue
GROUP BY priority_tier, source_type
ORDER BY priority_tier, source_type;
"
