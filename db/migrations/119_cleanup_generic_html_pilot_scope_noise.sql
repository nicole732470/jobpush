BEGIN;

WITH noisy AS (
    SELECT posting.site_id, posting.external_job_id
    FROM jobpush.job_postings posting
    JOIN jobpush.career_sites site USING (site_id)
    WHERE site.reviewed_by = 'system:generic-html-us-link-pilot-v1'
      AND posting.active
      AND posting.title ~* '\m(about the role|europe|emea|apac|latam|canada|canadian|german|japanese|spanish|french|portuguese|italian|dutch|korean|hindi|mandarin)\M'
)
UPDATE jobpush.job_postings posting
SET active = FALSE,
    market_scope = 'non-US',
    closed_at = COALESCE(posting.closed_at, now()),
    updated_at = now()
FROM noisy
WHERE posting.site_id = noisy.site_id
  AND posting.external_job_id = noisy.external_job_id;

COMMIT;

SELECT
    COUNT(*) FILTER (WHERE active) AS active_pilot_jobs,
    COUNT(*) FILTER (WHERE NOT active) AS inactive_pilot_jobs
FROM jobpush.job_postings posting
JOIN jobpush.career_sites site USING (site_id)
WHERE site.reviewed_by = 'system:generic-html-us-link-pilot-v1';
