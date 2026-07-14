\set ON_ERROR_STOP on

\copy (SELECT job.canonical_name AS company, job.title, job.normalized_title, job.location, job.first_seen_at, job.last_seen_at, label.decision_reason, job.job_url FROM jobpush.dashboard_jobs_fast job LEFT JOIN jobpush.job_title_labels label USING (normalized_title) WHERE job.seniority_bucket = 'new_grad' AND job.role_status = 'non_target' ORDER BY job.first_seen_at DESC, job.canonical_name, job.title) TO '/tmp/new_grad_non_target.csv' CSV HEADER

\copy (SELECT job.canonical_name AS company, job.title, job.normalized_title, job.location, job.first_seen_at, job.last_seen_at, label.decision_reason, job.job_url FROM jobpush.dashboard_jobs_fast job LEFT JOIN jobpush.job_title_labels label USING (normalized_title) WHERE job.seniority_bucket = 'new_grad' AND job.role_status = 'review' ORDER BY job.first_seen_at DESC, job.canonical_name, job.title) TO '/tmp/new_grad_review.csv' CSV HEADER
