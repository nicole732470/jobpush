-- Refresh only live eligibility. The inventory is maintained by the crawl
-- pipeline; rebuilding it from historical postings makes the dashboard slow.
\if :{?refresh_since}
\else
\set refresh_since 'epoch'
\endif

BEGIN;

-- Snapshot rows are keyed by (site_id, external_job_id).  A hash join would
-- scan every historical raw HTML blob; indexed lookups are far cheaper here.
SET LOCAL enable_hashjoin = off;

WITH changed_keys AS MATERIALIZED (
  SELECT site_id, external_job_id
  FROM jobpush.dashboard_jobs_fast
  WHERE first_seen_at >= :'refresh_since'::timestamptz
  UNION
  SELECT fast.site_id, fast.external_job_id
  FROM jobpush.dashboard_jobs_fast fast
  JOIN jobpush.job_title_labels label USING(normalized_title)
  WHERE label.updated_at >= :'refresh_since'::timestamptz
  UNION
  SELECT fast.site_id, fast.external_job_id
  FROM jobpush.job_description_snapshots snapshot
  JOIN jobpush.dashboard_jobs_fast fast USING(site_id,external_job_id)
  WHERE snapshot.updated_at >= :'refresh_since'::timestamptz
), eligibility AS MATERIALIZED (
  SELECT fast.site_id, fast.external_job_id,
         (snapshot.cleaned_description ILIKE '%sponsor%'
          AND jobpush.is_explicit_no_sponsorship(snapshot.cleaned_description)) AS explicit_no_sponsorship,
         snapshot.scrape_status,
         label.classification_status,
         label.canonical_role
  FROM changed_keys changed
  JOIN jobpush.dashboard_jobs_fast fast USING(site_id,external_job_id)
  LEFT JOIN jobpush.job_title_labels label
    ON label.normalized_title = fast.normalized_title
  LEFT JOIN jobpush.job_description_snapshots snapshot
    ON snapshot.site_id = fast.site_id AND snapshot.external_job_id = fast.external_job_id
), classified AS MATERIALIZED (
  SELECT site_id, external_job_id,
         CASE
           WHEN classification_status = 'non_target' THEN 'non_target'
           WHEN scrape_status = 'succeeded' AND explicit_no_sponsorship THEN 'non_target'
           WHEN scrape_status = 'succeeded' THEN COALESCE(classification_status, 'review')
           ELSE 'review'
         END AS role_status,
         CASE
           WHEN classification_status <> 'non_target'
                AND scrape_status = 'succeeded' AND NOT explicit_no_sponsorship
           THEN canonical_role ELSE NULL END AS canonical_role
  FROM eligibility
)
UPDATE jobpush.dashboard_jobs_fast fast
SET role_status = classified.role_status,
    canonical_role = classified.canonical_role
FROM classified
WHERE fast.site_id = classified.site_id AND fast.external_job_id = classified.external_job_id
  AND (fast.role_status, fast.canonical_role) IS DISTINCT FROM (classified.role_status, classified.canonical_role);

COMMIT;
