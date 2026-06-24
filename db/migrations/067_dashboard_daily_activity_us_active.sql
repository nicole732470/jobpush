BEGIN;

CREATE OR REPLACE VIEW jobpush.dashboard_daily_activity AS
WITH days AS (
    SELECT generate_series(
        (current_date - 29)::timestamp,
        current_date::timestamp,
        interval '1 day'
    )::date AS activity_date
), jobs AS (
    SELECT
        (posting.first_seen_at AT TIME ZONE 'America/Chicago')::date AS activity_date,
        count(*) AS new_jobs,
        count(*) FILTER (WHERE COALESCE(label.classification_status, 'review') = 'target') AS new_target_jobs,
        count(*) FILTER (WHERE COALESCE(label.classification_status, 'review') = 'review') AS new_review_jobs
    FROM jobpush.job_postings_us posting
    LEFT JOIN jobpush.job_title_labels label USING (normalized_title)
    GROUP BY 1
), closed AS (
    SELECT
        (closed_at AT TIME ZONE 'America/Chicago')::date AS activity_date,
        count(*) AS closed_jobs
    FROM jobpush.job_postings
    WHERE closed_at IS NOT NULL
      AND market_scope = 'US'
    GROUP BY 1
), runs AS (
    SELECT
        (started_at AT TIME ZONE 'America/Chicago')::date AS activity_date,
        count(*) AS crawl_runs,
        count(*) FILTER (WHERE status = 'succeeded') AS successful_runs,
        count(*) FILTER (WHERE status = 'failed') AS failed_runs,
        COALESCE(sum(requests_count), 0) AS requests,
        COALESCE(sum(new_job_count), 0) AS run_reported_new_jobs
    FROM jobpush.crawl_runs
    GROUP BY 1
)
SELECT
    days.activity_date,
    COALESCE(jobs.new_jobs, 0) AS new_jobs,
    COALESCE(jobs.new_target_jobs, 0) AS new_target_jobs,
    COALESCE(jobs.new_review_jobs, 0) AS new_review_jobs,
    COALESCE(closed.closed_jobs, 0) AS closed_jobs,
    COALESCE(runs.crawl_runs, 0) AS crawl_runs,
    COALESCE(runs.successful_runs, 0) AS successful_runs,
    COALESCE(runs.failed_runs, 0) AS failed_runs,
    COALESCE(runs.requests, 0) AS requests,
    COALESCE(runs.run_reported_new_jobs, 0) AS run_reported_new_jobs
FROM days
LEFT JOIN jobs USING (activity_date)
LEFT JOIN closed USING (activity_date)
LEFT JOIN runs USING (activity_date)
ORDER BY days.activity_date DESC;

COMMENT ON VIEW jobpush.dashboard_daily_activity IS
    'Thirty days of Chicago-local crawl and active-US job-change metrics. New/review/target counts use job_postings_us.';

COMMIT;
