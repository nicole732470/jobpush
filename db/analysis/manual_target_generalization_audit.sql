\pset pager off

SELECT role_status, count(*) AS active_jobs, count(DISTINCT normalized_title) AS titles
FROM jobpush.dashboard_jobs_fast
WHERE normalized_title ~* '(^|[^a-z])(supply chain planner|supply management analyst|agriculture sales analyst|deployment strategist|investment analyst|technical support engineer)([^a-z]|$)'
GROUP BY 1
ORDER BY 1;

SELECT role_status, count(*) AS active_new_grad_jobs
FROM jobpush.dashboard_jobs_fast
WHERE seniority_bucket = 'new_grad'
GROUP BY 1
ORDER BY 1;
