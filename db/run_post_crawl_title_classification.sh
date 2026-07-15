#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/connect_rds.sh
source "$SCRIPT_DIR/lib/connect_rds.sh"
REFRESH_SINCE="${JOBPUSH_REFRESH_SINCE:-$(date -u -d '24 hours ago' +%FT%TZ)}"

echo "==> incremental post-crawl classification since $REFRESH_SINCE"

echo "==> refresh recent crawl target/review counts"
"${PSQL[@]}" -v ON_ERROR_STOP=1 -v refresh_since="$REFRESH_SINCE" -P pager=off <<'SQL'
WITH recent_runs AS (
    SELECT run_id, batch_id
    FROM jobpush.crawl_runs
    WHERE status = 'succeeded'
      AND finished_at >= :'refresh_since'::timestamptz
), refreshed_runs AS (
    UPDATE jobpush.crawl_runs run
    SET target_job_count = counts.target_jobs,
        review_job_count = counts.review_jobs
    FROM (
        SELECT recent.run_id,
               COUNT(*) FILTER (WHERE label.classification_status = 'target')::integer AS target_jobs,
               COUNT(*) FILTER (WHERE label.classification_status = 'review')::integer AS review_jobs
        FROM recent_runs recent
        JOIN jobpush.job_postings posting
          ON posting.last_run_id = recent.run_id
         AND posting.active
         AND posting.market_scope = 'US'
        JOIN jobpush.job_title_labels label USING (normalized_title)
        GROUP BY recent.run_id
    ) counts
    WHERE run.run_id = counts.run_id
    RETURNING run.batch_id
)
UPDATE jobpush.crawl_batches batch
SET target_job_count = run.target_job_count,
    review_job_count = run.review_job_count
FROM jobpush.crawl_runs run
WHERE run.batch_id = batch.batch_id
  AND batch.batch_id IN (SELECT batch_id FROM refreshed_runs);
SQL

echo "==> refresh dashboard jobs fast table"
"${PSQL[@]}" -v ON_ERROR_STOP=1 -v refresh_since="$REFRESH_SINCE" \
  -f "$SCRIPT_DIR/refresh/refresh_dashboard_jobs_fast.sql"
