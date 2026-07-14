\pset pager off

\echo '=== Job posting totals ==='
SELECT
    count(*) AS total_posting_rows,
    count(*) FILTER (WHERE active) AS active_rows,
    count(*) FILTER (WHERE NOT active) AS closed_rows,
    count(DISTINCT normalized_title) AS distinct_titles,
    count(DISTINCT normalized_title) FILTER (WHERE active) AS active_distinct_titles
FROM jobpush.job_postings;

\echo '=== Active US current-year jobs by title decision ==='
SELECT
    COALESCE(label.classification_status, 'review') AS role_status,
    count(*) AS active_jobs,
    count(DISTINCT posting.normalized_title) AS distinct_titles,
    count(DISTINCT posting.consolidation_key) AS companies
FROM jobpush.job_postings_us posting
LEFT JOIN jobpush.job_title_labels label USING (normalized_title)
WHERE posting.active
GROUP BY 1
ORDER BY active_jobs DESC;

\echo '=== Daily new / closed / active touch counts, last 14 days ==='
WITH days AS (
    SELECT generate_series(
        (now() AT TIME ZONE 'America/Chicago')::date - interval '13 days',
        (now() AT TIME ZONE 'America/Chicago')::date,
        interval '1 day'
    )::date AS day
), active_daily AS (
    SELECT
        (posting.first_seen_at AT TIME ZONE 'America/Chicago')::date AS day,
        count(*) AS new_rows,
        count(*) FILTER (WHERE COALESCE(label.classification_status, 'review') = 'target') AS new_target_rows,
        count(*) FILTER (WHERE COALESCE(label.classification_status, 'review') = 'review') AS new_review_rows
    FROM jobpush.job_postings_us posting
    LEFT JOIN jobpush.job_title_labels label USING (normalized_title)
    WHERE posting.first_seen_at >= now() - interval '15 days'
    GROUP BY 1
), seen_daily AS (
    SELECT
        (posting.last_seen_at AT TIME ZONE 'America/Chicago')::date AS day,
        count(*) AS seen_rows
    FROM jobpush.job_postings_us posting
    WHERE posting.last_seen_at >= now() - interval '15 days'
    GROUP BY 1
), closed_daily AS (
    SELECT
        (posting.closed_at AT TIME ZONE 'America/Chicago')::date AS day,
        count(*) AS closed_rows
    FROM jobpush.job_postings posting
    WHERE posting.closed_at >= now() - interval '15 days'
    GROUP BY 1
)
SELECT
    days.day,
    COALESCE(active_daily.new_rows, 0) AS new_rows,
    COALESCE(closed_daily.closed_rows, 0) AS closed_rows,
    COALESCE(seen_daily.seen_rows, 0) AS seen_rows,
    COALESCE(active_daily.new_target_rows, 0) AS new_target_rows,
    COALESCE(active_daily.new_review_rows, 0) AS new_review_rows
FROM days
LEFT JOIN active_daily USING (day)
LEFT JOIN seen_daily USING (day)
LEFT JOIN closed_daily USING (day)
ORDER BY days.day DESC;

\echo '=== Recent title label changes by source ==='
SELECT
    (history.changed_at AT TIME ZONE 'America/Chicago')::date AS changed_day,
    history.labeled_by,
    history.new_status,
    count(*) AS labels_changed
FROM jobpush.job_title_label_history history
WHERE history.changed_at >= now() - interval '14 days'
GROUP BY 1, 2, 3
ORDER BY changed_day DESC, labels_changed DESC;
