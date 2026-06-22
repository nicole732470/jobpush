BEGIN;

UPDATE jobpush.job_postings
SET active = TRUE,
    closed_at = NULL,
    updated_at = now()
WHERE site_id = 78
  AND market_scope = 'non-US'
  AND NOT active;

COMMIT;
