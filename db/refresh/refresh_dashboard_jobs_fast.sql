-- Refresh only live eligibility. The inventory is maintained by the crawl
-- pipeline; rebuilding it from historical postings makes the dashboard slow.
BEGIN;

WITH eligibility AS MATERIALIZED (
  SELECT fast.site_id, fast.external_job_id,
         CASE
           WHEN snapshot.scrape_status = 'succeeded'
                AND jobpush.is_explicit_no_sponsorship(snapshot.cleaned_description) THEN 'non_target'
           WHEN snapshot.scrape_status = 'succeeded' THEN COALESCE(label.classification_status, 'review')
           ELSE 'review'
         END AS role_status,
         CASE
           WHEN snapshot.scrape_status = 'succeeded'
                AND NOT jobpush.is_explicit_no_sponsorship(snapshot.cleaned_description)
           THEN label.canonical_role ELSE NULL END AS canonical_role
  FROM jobpush.dashboard_jobs_fast fast
  LEFT JOIN jobpush.job_title_labels label
    ON label.normalized_title = fast.normalized_title
  LEFT JOIN jobpush.job_description_snapshots snapshot
    ON snapshot.site_id = fast.site_id AND snapshot.external_job_id = fast.external_job_id
)
UPDATE jobpush.dashboard_jobs_fast fast
SET role_status = eligibility.role_status,
    canonical_role = eligibility.canonical_role
FROM eligibility
WHERE fast.site_id = eligibility.site_id AND fast.external_job_id = eligibility.external_job_id;

COMMIT;

SELECT count(*) AS dashboard_jobs_fast_rows FROM jobpush.dashboard_jobs_fast;
