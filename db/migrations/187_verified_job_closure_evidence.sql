BEGIN;

ALTER TABLE jobpush.job_postings
    ADD COLUMN IF NOT EXISTS closure_verified_at TIMESTAMPTZ;

COMMENT ON COLUMN jobpush.job_postings.closure_verified_at IS
    'Set only after the job URL directly confirms the posting is no longer available.';

-- Before direct-link verification existed, closed_job_count meant only that a
-- posting disappeared from one crawl response. Those historical counts are
-- not evidence of closure and must not be shown as confirmed closed jobs.
UPDATE jobpush.crawl_runs
SET closed_job_count = 0
WHERE started_at < TIMESTAMPTZ '2026-07-15 03:20:00+00'
  AND closed_job_count > 0;

COMMIT;
