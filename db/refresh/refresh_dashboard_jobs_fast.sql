-- Refresh only live eligibility. The inventory is maintained by the crawl
-- pipeline; rebuilding it from historical postings makes the dashboard slow.
BEGIN;

UPDATE jobpush.dashboard_jobs_fast fast
SET role_status = CASE
      WHEN snapshot.scrape_status = 'succeeded'
           AND jobpush.is_explicit_no_sponsorship(snapshot.cleaned_description) THEN 'non_target'
      WHEN snapshot.scrape_status = 'succeeded' THEN COALESCE(label.classification_status, 'review')
      ELSE 'review'
    END,
    canonical_role = CASE
      WHEN snapshot.scrape_status = 'succeeded'
           AND NOT jobpush.is_explicit_no_sponsorship(snapshot.cleaned_description)
      THEN label.canonical_role ELSE NULL END
FROM jobpush.job_postings posting
LEFT JOIN jobpush.job_title_labels label USING (normalized_title)
LEFT JOIN jobpush.job_description_snapshots snapshot
  ON snapshot.site_id = posting.site_id AND snapshot.external_job_id = posting.external_job_id
 AND snapshot.source_fingerprint = md5(concat_ws(E'\x1f','jd-v2-complete-content',posting.title,posting.location,
       posting.category,posting.job_url,posting.description_snippet,posting.posted_text,posting.employment_type))
WHERE posting.site_id = fast.site_id AND posting.external_job_id = fast.external_job_id;

COMMIT;

SELECT count(*) AS dashboard_jobs_fast_rows FROM jobpush.dashboard_jobs_fast;
