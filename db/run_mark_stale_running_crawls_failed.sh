#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/connect_rds.sh"

"${PSQL[@]}" -P pager=off -c "
WITH stale_runs AS (
    SELECT run_id, batch_id, site_id
    FROM jobpush.crawl_runs
    WHERE status = 'running'
      AND started_at < now() - interval '60 minutes'
),
updated_runs AS (
    UPDATE jobpush.crawl_runs run
    SET status = 'failed',
        error_code = 'stale_timeout',
        error_message = 'Marked failed because crawl run was still running after 60 minutes; likely interrupted scheduler/adapter process.',
        finished_at = COALESCE(finished_at, now())
    FROM stale_runs stale
    WHERE run.run_id = stale.run_id
    RETURNING run.run_id, run.batch_id, run.site_id
),
updated_targets AS (
    UPDATE jobpush.crawl_batch_targets target
    SET status = 'failed'
    FROM updated_runs run
    WHERE target.batch_id = run.batch_id
      AND target.site_id = run.site_id
    RETURNING target.batch_id
),
updated_batches AS (
    UPDATE jobpush.crawl_batches batch
    SET status = 'failed',
        failed_target_count = GREATEST(failed_target_count, 1),
        finished_at = COALESCE(finished_at, now())
    WHERE batch.status = 'running'
      AND batch.batch_id IN (SELECT DISTINCT batch_id FROM updated_runs)
    RETURNING batch.batch_id
)
UPDATE jobpush.career_sites site
SET crawl_status = 'failed',
    consecutive_failures = consecutive_failures + 1,
    last_error = 'stale_timeout: previous crawl run was still running after 60 minutes',
    updated_at = now(),
    next_crawl_at = now() + interval '6 hours'
WHERE site.site_id IN (SELECT DISTINCT site_id FROM updated_runs);

SELECT site.source_type,
       run.status,
       run.error_code,
       count(*) AS runs
FROM jobpush.crawl_runs run
JOIN jobpush.career_sites site USING (site_id)
WHERE run.started_at >= now() - interval '24 hours'
GROUP BY site.source_type, run.status, run.error_code
ORDER BY site.source_type, run.status, run.error_code;
"
