#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -P pager=off <<'SQL'
\echo '=== P2 due by source ==='
SELECT source_type, count(*) AS due_sites
FROM jobpush.crawl_schedule_queue
WHERE priority_tier = 'P2'
  AND is_due
  AND crawl_status <> 'running'
GROUP BY 1
ORDER BY due_sites DESC, source_type;

\echo '=== P2 failed enabled sites ==='
SELECT source_type,
       CASE
           WHEN coalesce(last_error, '') ILIKE '%timeout%' OR coalesce(last_error, '') ILIKE '%timed out%' THEN 'timeout'
           WHEN coalesce(last_error, '') ILIKE '%404%' THEN '404'
           WHEN coalesce(last_error, '') ILIKE '%403%' OR coalesce(last_error, '') ILIKE '%forbidden%' THEN 'blocked'
           WHEN coalesce(last_error, '') ILIKE '%empty%' THEN 'empty'
           ELSE 'other'
       END AS reason,
       count(*) AS failed_sites
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier = 'P2'
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
  AND site.crawl_status = 'failed'
GROUP BY 1, 2
ORDER BY failed_sites DESC, source_type, reason;

\echo '=== P2 iCIMS / Workday / Gusto state ==='
SELECT source_type, verification_status, crawl_enabled, crawl_status, count(*) AS sites
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE target.enabled
  AND target.priority_tier = 'P2'
  AND source_type IN ('icims', 'workday', 'gusto')
GROUP BY 1, 2, 3, 4
ORDER BY 1, 2, 3, 4;
SQL
