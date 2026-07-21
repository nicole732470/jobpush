BEGIN;

UPDATE jobpush.job_postings posting
SET job_url = snapshot.apply_url,
    updated_at = now()
FROM jobpush.job_description_snapshots snapshot
JOIN jobpush.career_sites site USING (site_id)
WHERE posting.site_id = snapshot.site_id
  AND posting.external_job_id = snapshot.external_job_id
  AND site.source_type = 'smartrecruiters'
  AND posting.job_url ~ '^https?://api\.smartrecruiters\.com/'
  AND snapshot.scrape_status = 'succeeded'
  AND snapshot.apply_url ~ '^https?://jobs\.smartrecruiters\.com/';

UPDATE jobpush.job_description_snapshots snapshot
SET source_fingerprint = md5(concat_ws(E'\x1f','jd-v2-complete-content',posting.title,posting.location,posting.category,
    posting.job_url,posting.description_snippet,posting.posted_text,posting.employment_type)),
    updated_at = now()
FROM jobpush.job_postings posting
JOIN jobpush.career_sites site USING (site_id)
WHERE snapshot.site_id = posting.site_id
  AND snapshot.external_job_id = posting.external_job_id
  AND site.source_type = 'smartrecruiters'
  AND posting.job_url ~ '^https?://jobs\.smartrecruiters\.com/';

UPDATE jobpush.dashboard_jobs_fast fast
SET job_url = posting.job_url
FROM jobpush.job_postings posting
WHERE fast.site_id = posting.site_id
  AND fast.external_job_id = posting.external_job_id
  AND fast.job_url IS DISTINCT FROM posting.job_url;

COMMIT;

SELECT count(*) AS remaining_api_links
FROM jobpush.job_postings posting
JOIN jobpush.career_sites site USING (site_id)
WHERE site.source_type = 'smartrecruiters'
  AND posting.job_url ~ '^https?://api\.smartrecruiters\.com/';
