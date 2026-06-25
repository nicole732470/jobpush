\pset pager off

\echo '=== Latest rollout since 2026-06-24 23:27 UTC ==='
SELECT site.source_type, run.status, count(*) AS sites,
       sum(run.parsed_job_count) AS parsed_jobs,
       sum(run.new_job_count) AS new_jobs,
       sum(run.target_job_count) AS target_jobs,
       sum(run.review_job_count) AS review_jobs
FROM jobpush.crawl_runs run
JOIN jobpush.career_sites site USING (site_id)
WHERE run.started_at >= timestamptz '2026-06-24 23:27:00+00'
GROUP BY site.source_type, run.status
ORDER BY site.source_type, run.status;

\echo '=== Current enabled-company crawl coverage ==='
WITH sites AS (
    SELECT consolidation_key,
           bool_or(verification_status='verified' AND crawl_enabled) AS enabled_site,
           bool_or(last_crawled_at IS NOT NULL) AS attempted,
           bool_or(last_success_at IS NOT NULL) AS succeeded,
           bool_or(crawl_status='failed') AS failed
    FROM jobpush.career_sites GROUP BY consolidation_key
)
SELECT target.priority_tier, count(*) AS companies,
       count(*) FILTER (WHERE sites.enabled_site) AS with_enabled_site,
       count(*) FILTER (WHERE sites.attempted) AS attempted,
       count(*) FILTER (WHERE sites.succeeded) AS succeeded,
       count(*) FILTER (WHERE sites.failed) AS failed
FROM jobpush.crawl_targets target
LEFT JOIN sites USING (consolidation_key)
WHERE target.enabled
GROUP BY 1 ORDER BY 1;

\echo '=== Scheduler backlog ==='
SELECT priority_tier, source_type,
       count(*) FILTER (WHERE is_due) AS due_sites,
       count(*) AS schedulable_sites
FROM jobpush.crawl_schedule_queue
GROUP BY 1,2 ORDER BY 1,2;
