#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -v ON_ERROR_STOP=1 -P pager=off <<'SQL'
SELECT site.source_type,
       target.priority_tier,
       COUNT(*) AS enabled_sites,
       COUNT(*) FILTER (WHERE site.last_success_at IS NOT NULL) AS succeeded_once,
       COUNT(*) FILTER (WHERE site.crawl_status = 'failed') AS failed_sites,
       COUNT(*) FILTER (WHERE queue.is_due) AS still_due
FROM jobpush.career_sites site
JOIN jobpush.crawl_targets target USING (consolidation_key)
LEFT JOIN jobpush.crawl_schedule_queue queue USING (site_id)
WHERE site.source_type IN ('jobscore', 'dover')
  AND site.verification_status = 'verified'
  AND site.crawl_enabled
GROUP BY 1, 2
ORDER BY 1, 2;

SELECT site.source_type,
       COUNT(*) AS runs,
       SUM(run.raw_job_count) AS raw_jobs,
       SUM(run.target_job_count) AS target_jobs,
       SUM(run.review_job_count) AS review_jobs,
       SUM(run.new_job_count) AS new_jobs,
       COUNT(*) FILTER (WHERE run.status = 'failed') AS failures
FROM jobpush.crawl_runs run
JOIN jobpush.career_sites site USING (site_id)
WHERE site.source_type IN ('jobscore', 'dover')
  AND run.finished_at >= now() - interval '2 hours'
GROUP BY 1
ORDER BY 1;

SELECT reviewed_by, source_type, verification_status, crawl_enabled, COUNT(*) AS sites
FROM jobpush.career_sites
WHERE reviewed_by IN (
    'system:jobscore-parser-v1',
    'system:dover-api-parser-v1',
    'system:applicantmanager-root-cleanup-v1'
)
GROUP BY 1, 2, 3, 4
ORDER BY 1, 2, 3, 4;
SQL
