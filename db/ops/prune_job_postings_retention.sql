\pset pager off
\if :{?apply_delete}
\else
    \set apply_delete false
\endif

BEGIN;

CREATE TEMP TABLE retention_delete_candidates ON COMMIT DROP AS
WITH labeled AS (
    SELECT
        posting.site_id,
        posting.external_job_id,
        posting.market_scope,
        COALESCE(label.classification_status, 'review') AS role_status,
        posting.closed_at
    FROM jobpush.job_postings posting
    LEFT JOIN jobpush.job_title_labels label USING (normalized_title)
    WHERE NOT posting.active
      AND posting.closed_at IS NOT NULL
      AND NOT EXISTS (
          SELECT 1
          FROM jobpush.job_application_actions action
          WHERE action.site_id = posting.site_id
            AND action.external_job_id = posting.external_job_id
      )
)
SELECT site_id,
       external_job_id,
       CASE
           WHEN market_scope IS DISTINCT FROM 'US'
                AND closed_at < now() - interval '30 days'
               THEN 'closed_non_us_or_unknown_30d'
           WHEN role_status = 'non_target'
                AND closed_at < now() - interval '30 days'
               THEN 'closed_non_target_30d'
           WHEN role_status = 'review'
                AND closed_at < now() - interval '180 days'
               THEN 'closed_review_180d'
       END AS retention_reason
FROM labeled
WHERE (
       market_scope IS DISTINCT FROM 'US'
       AND closed_at < now() - interval '30 days'
      )
   OR (
       role_status = 'non_target'
       AND closed_at < now() - interval '30 days'
      )
   OR (
       role_status = 'review'
       AND closed_at < now() - interval '180 days'
      );

\echo '=== prune candidates ==='
SELECT retention_reason, COUNT(*) AS postings
FROM retention_delete_candidates
GROUP BY retention_reason
ORDER BY postings DESC;

\if :apply_delete
    \echo '=== deleting candidates ==='
    DELETE FROM jobpush.job_postings posting
    USING retention_delete_candidates candidate
    WHERE posting.site_id = candidate.site_id
      AND posting.external_job_id = candidate.external_job_id;
\else
    \echo 'Dry run only. Re-run with APPLY_RETENTION_DELETE=true to delete.'
\endif

COMMIT;

