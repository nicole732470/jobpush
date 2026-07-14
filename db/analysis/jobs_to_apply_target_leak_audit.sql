\pset pager off

\echo '=== Target jobs in explicitly non-target role families ==='
SELECT role_family, count(*) AS active_jobs, count(DISTINCT normalized_title) AS titles
FROM jobpush.dashboard_jobs_fast
WHERE role_status = 'target'
  AND role_family IN ('software_engineering', 'program_manager', 'project_manager')
GROUP BY 1
ORDER BY active_jobs DESC;

\echo '=== Explicit title-pattern leaks ==='
SELECT label.classification_status, label.rule_version, label.decision_reason,
       posting.normalized_title, count(*) AS active_jobs
FROM jobpush.job_postings_us posting
JOIN jobpush.job_title_labels label USING (normalized_title)
WHERE posting.active
  AND label.classification_status = 'target'
  AND lower(posting.normalized_title) ~ '(^engineer$|(^|[^a-z])(ios (software )?(engineer|developer)|android (software )?(engineer|developer)|mobile (software )?(engineer|developer)|administrative assistant|admin assistant|project manager|program manager|project management|program management|it operations management|cyber[ -]?security engineer)([^a-z]|$))'
GROUP BY 1,2,3,4
ORDER BY active_jobs DESC, posting.normalized_title;
