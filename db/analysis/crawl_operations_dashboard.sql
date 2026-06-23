\echo '=== Schedulable sites ==='
SELECT priority_tier, source_type, count(*) AS sites,
       count(*) FILTER (WHERE is_due) AS due
FROM jobpush.crawl_schedule_queue
GROUP BY priority_tier, source_type
ORDER BY priority_tier, source_type;

\echo '=== Adapter health, trailing 7 days ==='
SELECT * FROM jobpush.crawl_adapter_health ORDER BY source_type;

\echo '=== Active alerts ==='
SELECT * FROM jobpush.crawl_site_alerts
ORDER BY CASE priority_tier WHEN 'P0' THEN 0 WHEN 'P1' THEN 1 ELSE 2 END,
         canonical_name;

\echo '=== Per-site repeat-run evidence ==='
SELECT target.priority_tier, target.canonical_name, site.source_type, site.site_id,
       count(run.run_id) AS total_runs,
       count(*) FILTER (WHERE run.status = 'succeeded') AS succeeded_runs,
       max(run.started_at) AS last_run_at,
       max(run.parsed_job_count) FILTER (WHERE run.status = 'succeeded') AS max_parsed_jobs,
       min(run.parsed_job_count) FILTER (WHERE run.status = 'succeeded') AS min_parsed_jobs
FROM jobpush.crawl_schedule_queue target
JOIN jobpush.career_sites site USING (site_id)
LEFT JOIN jobpush.crawl_runs run USING (site_id)
GROUP BY target.priority_tier, target.canonical_name, site.source_type, site.site_id
ORDER BY target.priority_tier, site.source_type, target.canonical_name;

\echo '=== Title classification ==='
SELECT classification_status, count(*) AS normalized_titles,
       sum(active_posting_count) AS active_postings
FROM jobpush.job_title_catalog
GROUP BY classification_status
ORDER BY classification_status;
