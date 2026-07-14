\pset pager off

SELECT role_status, role_family, count(*) AS active_jobs,
       count(DISTINCT normalized_title) AS titles
FROM jobpush.dashboard_jobs_fast
WHERE normalized_title ~* '(^|[^a-z])forward[ -]+deployed([^a-z]|$)'
GROUP BY 1,2
ORDER BY active_jobs DESC;
