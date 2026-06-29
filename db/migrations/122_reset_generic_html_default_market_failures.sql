BEGIN;

UPDATE jobpush.career_sites site
SET crawl_status = 'pending',
    consecutive_failures = 0,
    last_error = NULL,
    next_crawl_at = now(),
    updated_at = now()
WHERE site.source_type = 'generic_html'
  AND site.reviewed_by LIKE 'system:generic-html-us-link-pilot-v%'
  AND site.crawl_status = 'failed'
  AND site.last_error LIKE '%unrecognized arguments: --default-market%';

UPDATE jobpush.crawl_runs run
SET error_code = 'superseded_runner_compatibility',
    error_message = concat_ws('; ', run.error_message, 'Reset by migration 122 after generic_html runner stopped passing --default-market')
FROM jobpush.career_sites site
WHERE run.site_id = site.site_id
  AND site.source_type = 'generic_html'
  AND site.reviewed_by LIKE 'system:generic-html-us-link-pilot-v%'
  AND run.status = 'failed'
  AND run.error_message LIKE '%unrecognized arguments: --default-market%';

COMMIT;

SELECT priority_tier, source_type, COUNT(*) AS due_sites
FROM jobpush.crawl_schedule_queue
WHERE is_due
GROUP BY 1, 2
ORDER BY 1, 2;
