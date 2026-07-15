BEGIN;

CREATE TEMP TABLE unverified_closure_runs ON COMMIT DROP AS
SELECT run_id
FROM jobpush.crawl_runs
WHERE started_at >= TIMESTAMPTZ '2026-07-14 05:00:00+00'
  AND started_at < TIMESTAMPTZ '2026-07-15 03:20:00+00'
  AND closed_job_count > 0;

-- Before closure verification was deployed, absence from one crawl result was
-- treated as closure. Reopen those rows because their job URLs were never
-- checked directly.
WITH reopened AS (
    UPDATE jobpush.job_postings posting
    SET active = TRUE,
        closed_at = NULL,
        updated_at = now()
    FROM unverified_closure_runs run
    WHERE posting.last_run_id = run.run_id
      AND NOT posting.active
      AND posting.closed_at >= TIMESTAMPTZ '2026-07-14 05:00:00+00'
      AND posting.closed_at < TIMESTAMPTZ '2026-07-15 03:20:00+00'
    RETURNING posting.job_url
)
SELECT count(*) AS reopened_rows,
       count(DISTINCT job_url) AS reopened_urls
FROM reopened;

UPDATE jobpush.crawl_runs crawl
SET closed_job_count = 0
FROM unverified_closure_runs run
WHERE crawl.run_id = run.run_id;

COMMIT;

SELECT count(*) AS remaining_closed_rows
FROM jobpush.job_postings
WHERE closed_at >= TIMESTAMPTZ '2026-07-14 05:00:00+00'
  AND closed_at < TIMESTAMPTZ '2026-07-15 03:20:00+00';

SELECT coalesce(sum(closed_job_count), 0) AS corrected_closed_today
FROM jobpush.crawl_runs
WHERE started_at >= TIMESTAMPTZ '2026-07-14 05:00:00+00';
