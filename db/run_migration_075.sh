#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -f "$SCRIPT_DIR/migrations/075_workable_adapter_schedule.sql"
"${PSQL[@]}" -P pager=off -c "
SELECT verification_status, reviewed_by, normalized_domain, source_type,
       count(*) AS sites, count(DISTINCT consolidation_key) AS companies
FROM jobpush.career_sites
WHERE source_type='workable'
GROUP BY verification_status, reviewed_by, normalized_domain, source_type
ORDER BY verification_status, reviewed_by NULLS LAST, normalized_domain;

SELECT priority_tier, source_type, count(*) AS due_sites
FROM jobpush.crawl_schedule_queue
WHERE is_due AND source_type='workable'
GROUP BY priority_tier, source_type
ORDER BY priority_tier;
"
