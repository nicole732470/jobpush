\pset pager off

\echo '=== job_postings storage by status ==='
WITH labeled AS (
    SELECT
        posting.active,
        posting.market_scope,
        COALESCE(label.classification_status, 'review') AS role_status,
        jobpush.posting_is_current_year(posting.posted_text) AS current_year,
        posting.first_seen_at,
        posting.last_seen_at,
        posting.closed_at,
        posting.description_snippet
    FROM jobpush.job_postings posting
    LEFT JOIN jobpush.job_title_labels label USING (normalized_title)
)
SELECT active,
       market_scope,
       role_status,
       current_year,
       COUNT(*) AS postings,
       MIN(first_seen_at) AS first_seen_min,
       MAX(last_seen_at) AS last_seen_max,
       COUNT(*) FILTER (WHERE closed_at IS NOT NULL) AS closed_postings,
       pg_size_pretty(SUM(length(COALESCE(description_snippet, '')))::bigint) AS snippet_text_size
FROM labeled
GROUP BY active, market_scope, role_status, current_year
ORDER BY active DESC, postings DESC;

\echo '=== retention deletion candidates ==='
WITH labeled AS (
    SELECT
        posting.site_id,
        posting.external_job_id,
        posting.market_scope,
        COALESCE(label.classification_status, 'review') AS role_status,
        posting.closed_at,
        posting.description_snippet
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
), candidates AS (
    SELECT *,
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
)
SELECT retention_reason,
       COUNT(*) AS postings,
       MIN(closed_at) AS oldest_closed_at,
       MAX(closed_at) AS newest_closed_at,
       pg_size_pretty(SUM(length(COALESCE(description_snippet, '')))::bigint) AS snippet_text_size
FROM candidates
WHERE retention_reason IS NOT NULL
GROUP BY retention_reason
ORDER BY postings DESC;

\echo '=== active non-target/non-US rows retained for future closed detection ==='
SELECT posting.market_scope,
       COALESCE(label.classification_status, 'review') AS role_status,
       COUNT(*) AS active_postings
FROM jobpush.job_postings posting
LEFT JOIN jobpush.job_title_labels label USING (normalized_title)
WHERE posting.active
  AND (posting.market_scope IS DISTINCT FROM 'US'
       OR COALESCE(label.classification_status, 'review') = 'non_target')
GROUP BY posting.market_scope, COALESCE(label.classification_status, 'review')
ORDER BY active_postings DESC;

