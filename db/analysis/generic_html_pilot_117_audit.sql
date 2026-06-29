\pset pager off

\echo '=== generic_html pilot run summary ==='
SELECT
    count(*) AS runs,
    count(*) FILTER (WHERE run.status = 'succeeded') AS succeeded,
    count(*) FILTER (WHERE run.status = 'failed') AS failed,
    sum(run.raw_job_count) AS raw_jobs,
    sum(run.target_job_count) AS target_jobs,
    sum(run.review_job_count) AS review_jobs,
    round(avg(run.latency_ms)) AS avg_latency_ms
FROM jobpush.crawl_runs run
JOIN jobpush.career_sites site USING (site_id)
WHERE run.adapter_name = 'generic-jsonld'
  AND site.reviewed_by LIKE 'system:generic-html-us-link-pilot-v%'
  AND run.started_at >= now() - interval '2 hours';

\echo '=== generic_html pilot current site status ==='
SELECT
    site.crawl_status,
    count(*) AS sites,
    count(*) FILTER (WHERE site.last_success_at IS NOT NULL) AS ever_succeeded,
    count(*) FILTER (WHERE site.last_error IS NOT NULL) AS has_current_error
FROM jobpush.career_sites site
WHERE site.reviewed_by LIKE 'system:generic-html-us-link-pilot-v%'
GROUP BY site.crawl_status
ORDER BY site.crawl_status;

\echo '=== generic_html pilot failures ==='
SELECT
    target.priority_tier,
    target.canonical_name,
    site.site_url,
    site.last_error,
    run.error_message
FROM jobpush.crawl_runs run
JOIN jobpush.career_sites site USING (site_id)
JOIN jobpush.crawl_targets target USING (consolidation_key)
WHERE run.adapter_name = 'generic-jsonld'
  AND site.reviewed_by LIKE 'system:generic-html-us-link-pilot-v%'
  AND run.status = 'failed'
  AND site.crawl_status = 'failed'
  AND run.started_at >= now() - interval '2 hours'
ORDER BY run.started_at DESC;

\echo '=== generic_html pilot parsed jobs ==='
SELECT
    target.priority_tier,
    target.canonical_name,
    posting.active,
    posting.title,
    posting.location,
    label.classification_status,
    posting.job_url
FROM jobpush.job_postings posting
JOIN jobpush.career_sites site USING (site_id)
JOIN jobpush.crawl_targets target
  ON target.consolidation_key = site.consolidation_key
LEFT JOIN jobpush.job_title_labels label USING (normalized_title)
WHERE site.reviewed_by LIKE 'system:generic-html-us-link-pilot-v%'
  AND posting.last_seen_at >= now() - interval '2 hours'
ORDER BY target.priority_score DESC, target.canonical_name, posting.title
LIMIT 80;

\echo '=== remaining due generic_html ==='
SELECT priority_tier, source_type, count(*) AS due_sites
FROM jobpush.crawl_schedule_queue
WHERE is_due
  AND source_type = 'generic_html'
GROUP BY 1, 2
ORDER BY 1, 2;
