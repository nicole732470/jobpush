#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"
"${PSQL[@]}" -P pager=off <<'SQL'
\echo === Due leftover by source / never_succeeded / consecutive_failures ===
SELECT source_type,
       count(*) AS due_n,
       count(*) FILTER (WHERE last_success_at IS NULL) AS never_ok,
       round(avg(consecutive_failures)::numeric,1) AS avg_fails,
       count(*) FILTER (WHERE consecutive_failures >= 3) AS fails_ge3
FROM jobpush.crawl_schedule_queue
WHERE is_due AND crawl_status <> 'running' AND priority_tier='P2'
GROUP BY 1 ORDER BY due_n DESC;

\echo === Sample due leftover ===
SELECT site_id, source_type, consecutive_failures,
       last_success_at IS NULL AS never_ok,
       crawl_status,
       left(coalesce(last_error,''),80) AS err,
       next_crawl_at
FROM jobpush.crawl_schedule_queue
WHERE is_due AND crawl_status <> 'running' AND priority_tier='P2'
ORDER BY consecutive_failures DESC NULLS LAST, site_id
LIMIT 15;
SQL
