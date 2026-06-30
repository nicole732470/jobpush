\pset pager off

SELECT
    (started_at AT TIME ZONE 'America/Chicago')::date AS chicago_day,
    cohort,
    count(*) AS runs,
    sum(target_count) AS target_count,
    sum(candidate_count) AS candidate_count,
    sum(error_count) AS error_count,
    sum(estimated_credits) AS estimated_credits,
    min(started_at AT TIME ZONE 'America/Chicago') AS first_run_ct,
    max(started_at AT TIME ZONE 'America/Chicago') AS last_run_ct
FROM jobpush.career_site_discovery_runs
WHERE estimated_credits > 0
GROUP BY 1, 2
ORDER BY chicago_day DESC, first_run_ct DESC, cohort;

\echo '=== Paid Tavily runs today CT ==='
SELECT
    run_id,
    cohort,
    target_count,
    candidate_count,
    error_count,
    estimated_credits,
    started_at AT TIME ZONE 'America/Chicago' AS started_ct
FROM jobpush.career_site_discovery_runs
WHERE estimated_credits > 0
  AND (started_at AT TIME ZONE 'America/Chicago')::date = (now() AT TIME ZONE 'America/Chicago')::date
ORDER BY started_at;
