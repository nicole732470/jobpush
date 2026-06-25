\pset pager off

SELECT 'candidate_stage' AS table_name, run_id, count(*) AS rows
FROM jobpush.career_site_discovery_stage
GROUP BY run_id
UNION ALL
SELECT 'result_stage' AS table_name, run_id, count(*) AS rows
FROM jobpush.career_site_discovery_result_stage
GROUP BY run_id
ORDER BY run_id, table_name;
