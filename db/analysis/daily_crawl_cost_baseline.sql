\pset pager off

SELECT count(*) FILTER (WHERE enabled) AS enabled_companies,
       count(*) FILTER (WHERE enabled AND priority_tier IN ('P0','P1','P2','P3')) AS priority_companies
FROM jobpush.crawl_targets;

SELECT count(DISTINCT consolidation_key) AS crawlable_companies,
       count(*) AS crawlable_sites
FROM jobpush.career_sites
WHERE verification_status = 'verified' AND crawl_enabled;

SELECT date_trunc('day', run.started_at) AS utc_day,
       count(*) AS runs,
       count(DISTINCT site.consolidation_key) AS companies,
       count(*) FILTER (WHERE run.status = 'succeeded') AS succeeded,
       sum(run.requests_count) AS requests,
       sum(run.pages_fetched) AS pages,
       sum(run.parsed_job_count) AS parsed_jobs,
       sum(run.new_job_count) AS new_jobs,
       sum(run.updated_job_count) AS updated_jobs,
       sum(run.closed_job_count) AS closed_jobs,
       round(sum(run.latency_ms)::numeric / 1000 / 3600, 2) AS total_adapter_hours
FROM jobpush.crawl_runs run
JOIN jobpush.career_sites site USING (site_id)
WHERE run.started_at >= now() - interval '7 days'
GROUP BY 1
ORDER BY 1 DESC;

SELECT pg_size_pretty(pg_database_size(current_database())) AS database_size,
       pg_database_size(current_database()) AS database_bytes;

SELECT pg_size_pretty(pg_total_relation_size('jobpush.job_postings')) AS job_postings_size,
       pg_size_pretty(pg_total_relation_size('jobpush.crawl_runs')) AS crawl_runs_size;
