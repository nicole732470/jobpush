\pset pager off

SELECT pid, state, wait_event_type, wait_event,
       pg_blocking_pids(pid) AS blocking_pids,
       now() - query_start AS query_age,
       left(query, 180) AS query
FROM pg_stat_activity
WHERE datname = current_database()
  AND (query ILIKE '%title_rule_reconciliation%'
       OR query ILIKE '%profile_title_rule_terms%')
ORDER BY query_start;
