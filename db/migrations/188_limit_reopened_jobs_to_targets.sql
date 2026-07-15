BEGIN;

-- The one-time July 14 closure repair reopened every classification. Keep only
-- targets open; non-target/review rows remain inactive but are not confirmed
-- closed because their URLs were not checked directly.
WITH restored_to_inactive AS (
    UPDATE jobpush.job_postings posting
    SET active = FALSE,
        closed_at = NULL,
        closure_verified_at = NULL,
        updated_at = now()
    FROM jobpush.job_title_labels label
    WHERE posting.normalized_title = label.normalized_title
      AND posting.updated_at = TIMESTAMPTZ '2026-07-15 03:29:57.792775+00'
      AND label.classification_status <> 'target'
    RETURNING label.classification_status
)
SELECT classification_status, count(*) AS restored_rows
FROM restored_to_inactive
GROUP BY classification_status
ORDER BY classification_status;

COMMIT;
