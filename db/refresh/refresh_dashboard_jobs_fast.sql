-- Refresh only live eligibility. The inventory is maintained by the crawl
-- pipeline; rebuilding it from historical postings makes the dashboard slow.
BEGIN;

SET LOCAL enable_hashjoin = off;
SET LOCAL enable_mergejoin = off;

WITH current_postings AS MATERIALIZED (
  SELECT fast.site_id, fast.external_job_id, posting.normalized_title,
         posting.title, posting.location, posting.category, posting.job_url,
         posting.description_snippet, posting.posted_text, posting.employment_type
  FROM jobpush.dashboard_jobs_fast fast
  JOIN jobpush.job_postings posting
    ON posting.site_id = fast.site_id AND posting.external_job_id = fast.external_job_id
), eligibility AS MATERIALIZED (
  SELECT current_postings.site_id, current_postings.external_job_id,
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
  FROM current_postings
  LEFT JOIN jobpush.job_title_labels label USING (normalized_title)
  LEFT JOIN jobpush.job_description_snapshots snapshot
    ON snapshot.site_id = current_postings.site_id AND snapshot.external_job_id = current_postings.external_job_id
   AND snapshot.source_fingerprint = md5(concat_ws(E'\x1f','jd-v2-complete-content',current_postings.title,current_postings.location,
         current_postings.category,current_postings.job_url,current_postings.description_snippet,current_postings.posted_text,current_postings.employment_type))
)
UPDATE jobpush.dashboard_jobs_fast fast
SET role_status = eligibility.role_status,
    canonical_role = eligibility.canonical_role
FROM eligibility
WHERE fast.site_id = eligibility.site_id AND fast.external_job_id = eligibility.external_job_id;

COMMIT;

SELECT count(*) AS dashboard_jobs_fast_rows FROM jobpush.dashboard_jobs_fast;
