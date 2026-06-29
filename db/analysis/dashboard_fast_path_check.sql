\pset pager off

\echo '=== Home apply summary fast path ==='
WITH chicago_day AS (
    SELECT ((NOW() AT TIME ZONE 'America/Chicago')::date AT TIME ZONE 'America/Chicago') AS start_at
), open_jobs AS (
    SELECT *
    FROM jobpush.dashboard_jobs
    WHERE priority_tier = ANY(ARRAY['P0','P1'])
      AND role_status = 'target'
      AND application_status IN ('new','saved','apply_next')
), closed_today AS (
    SELECT count(*) AS closed_jobs_today
    FROM jobpush.job_postings posting
    JOIN jobpush.crawl_targets target USING (consolidation_key)
    CROSS JOIN chicago_day
    WHERE target.priority_tier = ANY(ARRAY['P0','P1'])
      AND posting.closed_at >= chicago_day.start_at
)
SELECT
    count(*) AS open_target_jobs,
    count(DISTINCT consolidation_key) AS companies,
    count(*) FILTER (WHERE first_seen_at >= chicago_day.start_at) AS newly_discovered_today,
    (SELECT closed_jobs_today FROM closed_today) AS closed_jobs_today,
    count(*) FILTER (
        WHERE canonical_role = 'candidate_profile_track: product'
           OR normalized_title LIKE '%product%manager%'
    ) AS product_manager_jobs
FROM open_jobs
CROSS JOIN chicago_day
;

\echo '=== Jobs to apply fast path ==='
SELECT site_id, external_job_id, canonical_name, title, first_seen_at, job_url
FROM jobpush.dashboard_jobs
WHERE first_seen_at >= ('2026-06-23'::date AT TIME ZONE 'America/Chicago')
  AND first_seen_at < (('2026-06-29'::date + 1) AT TIME ZONE 'America/Chicago')
  AND priority_tier = ANY(ARRAY['P0','P1'])
  AND role_status = ANY(ARRAY['target'])
  AND application_status = ANY(ARRAY['new','saved','apply_next'])
ORDER BY first_seen_at DESC, canonical_name, title
LIMIT 5;
