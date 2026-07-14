\pset pager off

\echo '=== New-grad jobs by role status ==='
SELECT role_status, count(*) AS active_jobs, count(DISTINCT consolidation_key) AS companies
FROM jobpush.dashboard_jobs_fast
WHERE seniority_bucket = 'new_grad'
GROUP BY 1
ORDER BY active_jobs DESC;

\echo '=== Target new-grad titles ==='
SELECT normalized_title, count(*) AS active_jobs, count(DISTINCT consolidation_key) AS companies
FROM jobpush.dashboard_jobs_fast
WHERE seniority_bucket = 'new_grad' AND role_status = 'target'
GROUP BY 1
ORDER BY active_jobs DESC, normalized_title;

\echo '=== Current new-grad titles ==='
SELECT normalized_title, count(*) AS active_jobs, count(DISTINCT consolidation_key) AS companies
FROM jobpush.dashboard_jobs_fast
WHERE seniority_bucket = 'new_grad'
GROUP BY 1
ORDER BY active_jobs DESC, normalized_title
LIMIT 100;

\echo '=== New-grad phrase candidates assigned elsewhere ==='
SELECT seniority_bucket, normalized_title, count(*) AS active_jobs,
       count(DISTINCT consolidation_key) AS companies
FROM jobpush.dashboard_jobs_fast
WHERE seniority_bucket <> 'new_grad'
  AND normalized_title ~* '(^|[^a-z])(new college grad(uate)?|graduate (hire|role|opportunity|scheme|development program|rotation(al)? program)|campus (hire|recruit|program|graduate)|university (hire|recruit|graduate|program)|college (hire|recruit|graduate)|class of 20[0-9]{2}|grad(uate)? 20[0-9]{2}|early talent)([^a-z]|$)'
GROUP BY 1,2
ORDER BY active_jobs DESC, normalized_title
LIMIT 150;
